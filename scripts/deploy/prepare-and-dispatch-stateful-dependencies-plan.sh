#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/prepare-and-dispatch-stateful-dependencies-plan.sh \
    --expected-head SHA

Verify the completed network and runtime-dependencies applies, resolve the
stateful tfvars from private network outputs, stop before mutation when any
same-name RDS/Cognito/security-group resource already exists, configure only
AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64, and dispatch the guarded plan.
No Terraform apply/destroy or secret-value write is performed.
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

read_tfvar_string() {
  local name="$1"
  sed -nE \
    "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" \
    "$FOUNDATION_TFVARS" |
    head -n 1
}

command_is_absent() {
  set +e
  "$@" >/dev/null 2>&1
  local status=$?
  set -e
  [[ "$status" -ne 0 ]]
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

[[ "$EXPECTED_HEAD" =~ ^[0-9a-f]{40}$ ]] || fail "EXPECTED_HEAD_INVALID"

for command_name in git gh aws cygpath sed grep head find sort tail cp sleep; do
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
WORKFLOW="runtime-contract-verification.yml"
BRANCH="agent/rdb-domain-realignment"
ENVIRONMENT="aws-live-plan"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
FOUNDATION_TFVARS="$PRIVATE_DIR/foundation.tfvars"
FOUNDATION_STATE="$PRIVATE_DIR/foundation.remote-post-migration.tfstate"
STATEFUL_EXAMPLE="$REPO_ROOT/infra/terraform/envs/backend-stateful-dependencies/live.tfvars.example"
STATEFUL_TFVARS="$PRIVATE_DIR/stateful-dependencies.live.tfvars"

[[ -f "$FOUNDATION_TFVARS" ]] || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
[[ -f "$FOUNDATION_STATE" ]] || fail "VERIFIED_FOUNDATION_STATE_NOT_FOUND"
[[ -f "$STATEFUL_EXAMPLE" ]] || fail "STATEFUL_DEPENDENCIES_TFVARS_EXAMPLE_NOT_FOUND"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "UNEXPECTED_CURRENT_BRANCH"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"

gh auth status --hostname github.com >/dev/null 2>&1 || fail "GITHUB_AUTH_UNAVAILABLE"
aws sts get-caller-identity --output json >/dev/null 2>&1 || fail "AWS_IDENTITY_UNAVAILABLE"

EXPECTED_ACCOUNT_ID="$(read_tfvar_string expected_aws_account_id)"
CALLER_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "EXPECTED_ACCOUNT_ID_INVALID"
[[ "$CALLER_ACCOUNT_ID" == "$EXPECTED_ACCOUNT_ID" ]] || fail "AWS_ACCOUNT_MISMATCH"

NETWORK_SUMMARY="$(find "$PRIVATE_DIR" -maxdepth 2 -type f -name network-apply-summary.txt -print 2>/dev/null | sort | tail -n 1)"
NETWORK_OUTPUTS="$(find "$PRIVATE_DIR" -maxdepth 2 -type f -name network-outputs.json -print 2>/dev/null | sort | tail -n 1)"
RUNTIME_SUMMARY="$(find "$PRIVATE_DIR" -maxdepth 2 -type f -name runtime-dependencies-apply-summary.txt -print 2>/dev/null | sort | tail -n 1)"

[[ -f "$NETWORK_SUMMARY" ]] || fail "SUCCESSFUL_NETWORK_APPLY_EVIDENCE_NOT_FOUND"
[[ -f "$NETWORK_OUTPUTS" ]] || fail "NETWORK_OUTPUT_EVIDENCE_NOT_FOUND"
[[ -f "$RUNTIME_SUMMARY" ]] || fail "SUCCESSFUL_RUNTIME_DEPENDENCIES_APPLY_EVIDENCE_NOT_FOUND"

grep -Fqx 'NetworkApplyStatus=success' "$NETWORK_SUMMARY" || fail "NETWORK_APPLY_NOT_SUCCESSFUL"
grep -Fqx 'CreatedResourceCount=16' "$NETWORK_SUMMARY" || fail "NETWORK_RESOURCE_COUNT_MISMATCH"
grep -Fqx 'PostApplyPlanNoChanges=true' "$NETWORK_SUMMARY" || fail "NETWORK_POST_APPLY_DRIFT_PRESENT"
grep -Fqx 'RuntimeDependenciesApplyStatus=success' "$RUNTIME_SUMMARY" || fail "RUNTIME_DEPENDENCIES_APPLY_NOT_SUCCESSFUL"
grep -Fqx 'CreatedResourceCount=13' "$RUNTIME_SUMMARY" || fail "RUNTIME_DEPENDENCIES_RESOURCE_COUNT_MISMATCH"
grep -Fqx 'SecretValueWriteExecuted=false' "$RUNTIME_SUMMARY" || fail "RUNTIME_SECRET_VALUE_BOUNDARY_MISSING"
grep -Fqx 'PostApplyPlanNoChanges=true' "$RUNTIME_SUMMARY" || fail "RUNTIME_DEPENDENCIES_POST_APPLY_DRIFT_PRESENT"

GITHUB_LOGIN="$(gh api user --jq .login)"
[[ -n "$GITHUB_LOGIN" ]] || fail "GITHUB_LOGIN_UNAVAILABLE"

"${PYTHON_CMD[@]}" - "$NETWORK_OUTPUTS" "$STATEFUL_EXAMPLE" "$STATEFUL_TFVARS" "$GITHUB_LOGIN" <<'PY'
import json
import re
import sys
from pathlib import Path

outputs_path = Path(sys.argv[1])
example_path = Path(sys.argv[2])
target_path = Path(sys.argv[3])
owner = sys.argv[4]

outputs = json.loads(outputs_path.read_text(encoding="utf-8"))

def value(name):
    entry = outputs.get(name)
    if not isinstance(entry, dict):
        raise SystemExit(f"NETWORK_OUTPUT_INVALID: {name}")
    return entry.get("value")

vpc_id = value("vpc_id")
subnet_ids = value("private_subnet_ids")
cidr_blocks = value("private_subnet_cidr_blocks")
if not isinstance(vpc_id, str) or not vpc_id.startswith("vpc-"):
    raise SystemExit("NETWORK_VPC_OUTPUT_INVALID")
if not isinstance(subnet_ids, list) or len(subnet_ids) != 2 or not all(isinstance(v, str) and v.startswith("subnet-") for v in subnet_ids):
    raise SystemExit("NETWORK_PRIVATE_SUBNET_OUTPUT_INVALID")
if not isinstance(cidr_blocks, list) or len(cidr_blocks) != 2 or not all(isinstance(v, str) and "/" in v for v in cidr_blocks):
    raise SystemExit("NETWORK_PRIVATE_CIDR_OUTPUT_INVALID")

text = example_path.read_text(encoding="utf-8")
text = text.replace('vpc_id = "vpc-replace-from-network-output"', f'vpc_id = "{vpc_id}"')
text = text.replace('"subnet-replace-private-a",', f'"{subnet_ids[0]}",')
text = text.replace('"subnet-replace-private-b",', f'"{subnet_ids[1]}",')
text = re.sub(
    r'allowed_database_cidr_blocks = \[\n(?:[ \t]+"[^"]+",?\n)+\]',
    'allowed_database_cidr_blocks = [\n'
    f'  "{cidr_blocks[0]}",\n'
    f'  "{cidr_blocks[1]}",\n'
    ']',
    text,
    count=1,
)
text = text.replace("replace-with-owner", owner)
if "replace-" in text or "0.0.0.0/0" in text or "::/0" in text:
    raise SystemExit("STATEFUL_TFVARS_PLACEHOLDER_OR_PUBLIC_CIDR_PRESENT")
target_path.write_text(text, encoding="utf-8")
PY

VPC_ID="$(sed -nE 's/^[[:space:]]*vpc_id[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$STATEFUL_TFVARS" | head -n 1)"
[[ "$VPC_ID" == vpc-* ]] || fail "STATEFUL_VPC_ID_INVALID"

NAME_PREFIX="terraformers-modernization-dev"
DB_SECURITY_GROUP_NAME="${NAME_PREFIX}-db"
DB_SUBNET_GROUP_NAME="${NAME_PREFIX}-db"
DB_INSTANCE_ID="${NAME_PREFIX}-mariadb"
COGNITO_POOL_NAME="${NAME_PREFIX}-users"

COLLISIONS=()
SG_ID="$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${DB_SECURITY_GROUP_NAME}" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)"
[[ -z "$SG_ID" || "$SG_ID" == "None" ]] || COLLISIONS+=("security-group")

command_is_absent aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" || COLLISIONS+=("db-subnet-group")
command_is_absent aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" || COLLISIONS+=("rds-instance")

COGNITO_POOL_ID="$(aws cognito-idp list-user-pools \
  --max-results 60 \
  --query "UserPools[?Name=='${COGNITO_POOL_NAME}'].Id | [0]" \
  --output text 2>/dev/null || true)"
[[ -z "$COGNITO_POOL_ID" || "$COGNITO_POOL_ID" == "None" ]] || COLLISIONS+=("cognito-user-pool")

STATE_RECORD="$(${PYTHON_CMD[@]} - "$FOUNDATION_STATE" <<'PY'
import json
import sys
from pathlib import Path
state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
outputs = state.get("outputs", {})
for name in ("terraform_state_bucket", "terraform_state_prefix"):
    entry = outputs.get(name, {})
    value = entry.get("value") if isinstance(entry, dict) else None
    if not isinstance(value, str) or not value:
        raise SystemExit(f"FOUNDATION_OUTPUT_INVALID: {name}")
print(outputs["terraform_state_bucket"]["value"])
print(outputs["terraform_state_prefix"]["value"].strip("/"))
PY
)"
STATE_BUCKET="$(sed -n '1p' <<< "$STATE_RECORD")"
STATE_PREFIX="$(sed -n '2p' <<< "$STATE_RECORD")"
STATE_KEY="${STATE_PREFIX}/stateful-dependencies/terraform.tfstate"
if aws s3api head-object --bucket "$STATE_BUCKET" --key "$STATE_KEY" >/dev/null 2>&1; then
  COLLISIONS+=("remote-state")
fi

if (( ${#COLLISIONS[@]} > 0 )); then
  printf '%s\n' \
    "StatefulDependenciesPlanPreparation=blocked" \
    "ExistingStatefulResourceCollision=true" \
    "CollisionTypes=$(IFS=,; echo "${COLLISIONS[*]}")" \
    "StatefulDependenciesSecretConfigured=false" \
    "TerraformPlanDispatched=false" \
    "TerraformApplyExecuted=false" \
    "TerraformDestroyExecuted=false" \
    "AwsMutation=none" \
    "GitHubMutation=none" >&2
  exit 2
fi

"${PYTHON_CMD[@]}" - "$STATEFUL_TFVARS" <<'PY' |
import base64
import sys
from pathlib import Path
sys.stdout.write(base64.b64encode(Path(sys.argv[1]).read_bytes()).decode("ascii"))
PY
  gh secret set AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64 \
    --env "$ENVIRONMENT" \
    --repo "$REPO"

bash scripts/deploy/inventory-live-aws-prerequisites.sh \
  --expected-head "$EXPECTED_HEAD" \
  --stage stateful-dependencies \
  --strict

gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref "$BRANCH" \
  -f execute_live_plan=true \
  -f plan_stage=stateful-dependencies \
  -f expected_aws_account_id="$EXPECTED_ACCOUNT_ID" \
  -f allow_destructive=false \
  -f allow_optional_adapters=false

RUN_RECORD=""
for _ in {1..10}; do
  RUN_RECORD="$(gh api \
    "repos/${REPO}/actions/workflows/${WORKFLOW}/runs?branch=${BRANCH}&event=workflow_dispatch&per_page=10" \
    --jq ".workflow_runs[] | select(.head_sha == \"${ACTUAL_HEAD}\") | [.id, .html_url, .status] | @tsv" \
    | head -n 1)"
  [[ -n "$RUN_RECORD" ]] && break
  sleep 2
done
[[ -n "$RUN_RECORD" ]] || fail "DISPATCHED_STATEFUL_PLAN_RUN_NOT_FOUND"

IFS=$'\t' read -r RUN_ID RUN_URL RUN_STATUS <<< "$RUN_RECORD"
[[ "$RUN_ID" =~ ^[0-9]+$ ]] || fail "DISPATCHED_STATEFUL_PLAN_RUN_ID_INVALID"
[[ -n "$RUN_URL" ]] || fail "DISPATCHED_STATEFUL_PLAN_RUN_URL_MISSING"

printf '%s\n' \
  "StatefulDependenciesPlanDispatch=success" \
  "RepositoryHead=${ACTUAL_HEAD:0:12}" \
  "NetworkApplyVerified=true" \
  "RuntimeDependenciesApplyVerified=true" \
  "ExistingStatefulResourceCollision=false" \
  "StatefulTfvarsPrivate=true" \
  "StatefulDependenciesSecretConfigured=true" \
  "EksAndFrontendSecretsConfigured=false" \
  "InventoryStage=stateful-dependencies" \
  "PrerequisiteStrict=passed" \
  "PlanStage=stateful-dependencies" \
  "ExpectedCreateResourceCount=5" \
  "AllowDestructive=false" \
  "AllowOptionalAdapters=false" \
  "EnvironmentApprovalRequired=true" \
  "RunId=${RUN_ID}" \
  "RunStatus=${RUN_STATUS}" \
  "RunUrl=${RUN_URL}" \
  "PythonCommand=${PYTHON_LABEL}" \
  "SensitiveValuesPrinted=false" \
  "TerraformApplyExecuted=false" \
  "TerraformDestroyExecuted=false" \
  "AwsMutation=read-only-preflight-and-plan" \
  "GitHubMutation=stateful-dependencies-secret"
