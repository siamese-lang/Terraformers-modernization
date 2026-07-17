#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/configure-github-live-plan-environment.sh \
    --expected-head SHA

Approved mutation scope:
- create/update GitHub environment aws-live-plan
- require the authenticated GitHub user as reviewer
- allow deployments only from main and the current pre-merge branch
- set four environment variables from verified foundation state
- create private network tfvars and set AWS_LIVE_NETWORK_TFVARS_B64
- run strict network prerequisite inventory

The command never prints variable or Secret values and performs no AWS mutation.
EOF
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

python_is_usable() {
  local output
  output="$("$@" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)" || return 1
  [[ "$output" =~ ^3\.[0-9]+$ ]]
}

EXPECTED_HEAD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-head)
      [[ $# -ge 2 ]] || fail "EXPECTED_HEAD_VALUE_MISSING"
      EXPECTED_HEAD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "UNKNOWN_ARGUMENT: $1"
      ;;
  esac
done

[[ -n "$EXPECTED_HEAD" ]] || fail "EXPECTED_HEAD_REQUIRED"

for command_name in git gh aws cygpath sed grep cp mktemp; do
  command -v "$command_name" >/dev/null 2>&1 || fail "REQUIRED_COMMAND_NOT_FOUND: $command_name"
done

PYTHON_CMD=()
PYTHON_LABEL=""
if command -v py >/dev/null 2>&1 && python_is_usable py -3; then
  PYTHON_CMD=(py -3)
  PYTHON_LABEL="py -3"
elif command -v python >/dev/null 2>&1 && python_is_usable python; then
  PYTHON_CMD=(python)
  PYTHON_LABEL="python"
elif command -v python3 >/dev/null 2>&1 && python_is_usable python3; then
  PYTHON_CMD=(python3)
  PYTHON_LABEL="python3"
else
  fail "USABLE_PYTHON3_NOT_FOUND"
fi

REPO="siamese-lang/Terraformers-modernization"
ENVIRONMENT="aws-live-plan"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
CURRENT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
REMOTE_STATE="$PRIVATE_DIR/foundation.remote-post-migration.tfstate"
NETWORK_EXAMPLE="$REPO_ROOT/infra/terraform/envs/aws-runtime-network/live.tfvars.example"
NETWORK_TFVARS="$PRIVATE_DIR/network.live.tfvars"
ENVIRONMENT_REQUEST="$PRIVATE_DIR/aws-live-plan.environment-request.json"
FOUNDATION_OUTPUTS="$PRIVATE_DIR/aws-live-plan.foundation-outputs.json"

[[ "$CURRENT_BRANCH" == "agent/rdb-domain-realignment" ]] || fail "UNEXPECTED_CURRENT_BRANCH: $CURRENT_BRANCH"
[[ -f "$REMOTE_STATE" ]] || fail "VERIFIED_REMOTE_FOUNDATION_STATE_NOT_FOUND"
[[ -f "$NETWORK_EXAMPLE" ]] || fail "NETWORK_TFVARS_EXAMPLE_NOT_FOUND"

cd "$REPO_ROOT"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}

ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"

gh auth status --hostname github.com >/dev/null 2>&1 || fail "GITHUB_AUTH_UNAVAILABLE"
aws sts get-caller-identity --output json >/dev/null 2>&1 || fail "AWS_IDENTITY_UNAVAILABLE"

GITHUB_LOGIN="$(gh api user --jq .login)"
GITHUB_USER_ID="$(gh api user --jq .id)"
[[ -n "$GITHUB_LOGIN" ]] || fail "GITHUB_LOGIN_UNAVAILABLE"
[[ "$GITHUB_USER_ID" =~ ^[0-9]+$ ]] || fail "GITHUB_USER_ID_INVALID"

mkdir -p "$PRIVATE_DIR"

"${PYTHON_CMD[@]}" - "$REMOTE_STATE" "$FOUNDATION_OUTPUTS" <<'PY'
import json
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
state = json.loads(state_path.read_text(encoding="utf-8"))
outputs = state.get("outputs", {})
required = {
    "AWS_REGION": "aws_region",
    "AWS_ROLE_TO_ASSUME": "terraform_plan_role_arn",
    "AWS_TERRAFORM_STATE_BUCKET": "terraform_state_bucket",
    "AWS_TERRAFORM_STATE_PREFIX": "terraform_state_prefix",
}
resolved = {}
for variable_name, output_name in required.items():
    entry = outputs.get(output_name)
    if not isinstance(entry, dict):
        raise SystemExit(f"FOUNDATION_OUTPUT_MISSING: {output_name}")
    value = entry.get("value")
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"FOUNDATION_OUTPUT_INVALID: {output_name}")
    resolved[variable_name] = value.strip()

if resolved["AWS_REGION"] != "ap-northeast-2":
    raise SystemExit("FOUNDATION_REGION_MISMATCH")
if not resolved["AWS_ROLE_TO_ASSUME"].startswith("arn:aws:iam::"):
    raise SystemExit("FOUNDATION_ROLE_ARN_INVALID")

output_path.write_text(json.dumps(resolved, indent=2) + "\n", encoding="utf-8")
PY

CALLER_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
ROLE_ACCOUNT="$("${PYTHON_CMD[@]}" - "$FOUNDATION_OUTPUTS" <<'PY'
import json
import sys
from pathlib import Path
value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["AWS_ROLE_TO_ASSUME"]
print(value.split(":")[4])
PY
)"
[[ "$CALLER_ACCOUNT" == "$ROLE_ACCOUNT" ]] || fail "FOUNDATION_ROLE_ACCOUNT_MISMATCH"

cp "$NETWORK_EXAMPLE" "$NETWORK_TFVARS"
sed -i "s/replace-with-owner/${GITHUB_LOGIN}/g" "$NETWORK_TFVARS"
grep -Fq 'enable_nat_gateway = true' "$NETWORK_TFVARS" || fail "NETWORK_NAT_BASELINE_MISSING"
grep -Fq 'single_nat_gateway = true' "$NETWORK_TFVARS" || fail "NETWORK_SINGLE_NAT_BASELINE_MISSING"
grep -Fq 'enable_bedrock_runtime_endpoint = false' "$NETWORK_TFVARS" || fail "NETWORK_OPTIONAL_ENDPOINT_GUARD_MISSING"
if grep -Eq 'replace-with|000000000000|0\.0\.0\.0/0|::/0' "$NETWORK_TFVARS"; then
  fail "NETWORK_TFVARS_PLACEHOLDER_OR_UNSAFE_VALUE_PRESENT"
fi

"${PYTHON_CMD[@]}" - "$ENVIRONMENT_REQUEST" "$GITHUB_USER_ID" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
user_id = int(sys.argv[2])
payload = {
    "wait_timer": 0,
    "prevent_self_review": False,
    "reviewers": [{"type": "User", "id": user_id}],
    "deployment_branch_policy": {
        "protected_branches": False,
        "custom_branch_policies": True,
    },
}
path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
PY

if ! gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  "repos/${REPO}/environments/${ENVIRONMENT}" \
  --input "$ENVIRONMENT_REQUEST" >/dev/null; then
  fail "GITHUB_ENVIRONMENT_CONFIGURATION_FAILED"
fi

ensure_branch_policy() {
  local branch_name="$1"
  local existing
  existing="$(gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    "repos/${REPO}/environments/${ENVIRONMENT}/deployment-branch-policies" \
    --jq ".branch_policies[] | select(.name == \"${branch_name}\") | .name" 2>/dev/null || true)"
  if [[ "$existing" != "$branch_name" ]]; then
    gh api \
      --method POST \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2026-03-10" \
      "repos/${REPO}/environments/${ENVIRONMENT}/deployment-branch-policies" \
      -f "name=${branch_name}" \
      -f "type=branch" >/dev/null
  fi
}

ensure_branch_policy "main"
ensure_branch_policy "$CURRENT_BRANCH"

set_environment_variable() {
  local name="$1"
  local value
  value="$("${PYTHON_CMD[@]}" - "$FOUNDATION_OUTPUTS" "$name" <<'PY'
import json
import sys
from pathlib import Path
payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(payload[sys.argv[2]], end="")
PY
)"
  printf '%s' "$value" | gh variable set "$name" --env "$ENVIRONMENT" --repo "$REPO"
}

set_environment_variable AWS_REGION
set_environment_variable AWS_ROLE_TO_ASSUME
set_environment_variable AWS_TERRAFORM_STATE_BUCKET
set_environment_variable AWS_TERRAFORM_STATE_PREFIX

"${PYTHON_CMD[@]}" - "$NETWORK_TFVARS" <<'PY' |
import base64
import sys
from pathlib import Path
sys.stdout.write(base64.b64encode(Path(sys.argv[1]).read_bytes()).decode("ascii"))
PY
  gh secret set AWS_LIVE_NETWORK_TFVARS_B64 \
    --env "$ENVIRONMENT" \
    --repo "$REPO"

rm -f "$ENVIRONMENT_REQUEST" "$FOUNDATION_OUTPUTS"

bash scripts/deploy/inventory-live-aws-prerequisites.sh \
  --expected-head "$EXPECTED_HEAD" \
  --stage network \
  --strict

ENVIRONMENT_EXISTS="$(gh api "repos/${REPO}/environments/${ENVIRONMENT}" --jq .name)"
[[ "$ENVIRONMENT_EXISTS" == "$ENVIRONMENT" ]] || fail "GITHUB_ENVIRONMENT_VERIFY_FAILED"

VARIABLE_COUNT="$(gh variable list --env "$ENVIRONMENT" --repo "$REPO" --json name --jq 'map(select(.name == "AWS_REGION" or .name == "AWS_ROLE_TO_ASSUME" or .name == "AWS_TERRAFORM_STATE_BUCKET" or .name == "AWS_TERRAFORM_STATE_PREFIX")) | length')"
SECRET_PRESENT="$(gh secret list --env "$ENVIRONMENT" --repo "$REPO" --json name --jq 'map(select(.name == "AWS_LIVE_NETWORK_TFVARS_B64")) | length')"
[[ "$VARIABLE_COUNT" == "4" ]] || fail "GITHUB_ENVIRONMENT_VARIABLE_VERIFY_FAILED"
[[ "$SECRET_PRESENT" == "1" ]] || fail "GITHUB_NETWORK_SECRET_VERIFY_FAILED"

printf '%s\n' \
  "GitHubEnvironmentConfiguration=success" \
  "RepositoryHead=${ACTUAL_HEAD:0:12}" \
  "Environment=${ENVIRONMENT}" \
  "RequiredReviewerConfigured=true" \
  "PreventSelfReview=false" \
  "AllowedBranchMain=true" \
  "AllowedBranchPreMerge=true" \
  "EnvironmentVariableCount=4" \
  "NetworkTfvarsSecretConfigured=true" \
  "NetworkPrerequisiteStrict=passed" \
  "LaterStageSecretsConfigured=false" \
  "SecretValuesPrinted=false" \
  "AwsMutation=none" \
  "GitHubMutation=environment-variables-network-secret"
