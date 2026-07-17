#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/apply-approved-live-network.sh \
    --expected-head CURRENT_SHA \
    --approved-plan-head PLAN_SHA

The command creates a fresh private Terraform working directory, rebuilds the
network plan with local AWS credentials, requires its resource actions to match
the reviewed GitHub plan exactly, applies that saved plan once, and verifies the
remote state and a no-change post-apply plan. It never runs terraform destroy.
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

EXPECTED_HEAD=""
APPROVED_PLAN_HEAD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-head)
      [[ $# -ge 2 ]] || fail "EXPECTED_HEAD_VALUE_MISSING"
      EXPECTED_HEAD="$2"
      shift 2
      ;;
    --approved-plan-head)
      [[ $# -ge 2 ]] || fail "APPROVED_PLAN_HEAD_VALUE_MISSING"
      APPROVED_PLAN_HEAD="$2"
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
[[ "$APPROVED_PLAN_HEAD" =~ ^[0-9a-f]{40}$ ]] || fail "APPROVED_PLAN_HEAD_INVALID"

for command_name in git gh aws cygpath sed grep head rm mkdir cp cmp sort sha256sum; do
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

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
BRANCH="agent/rdb-domain-realignment"
NETWORK_SOURCE="$REPO_ROOT/infra/terraform/envs/aws-runtime-network"
NETWORK_EXAMPLE="$NETWORK_SOURCE/live.tfvars.example"
SUMMARIZER="$REPO_ROOT/scripts/deploy/summarize-terraform-plan.py"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
FOUNDATION_TFVARS="$PRIVATE_DIR/foundation.tfvars"
FOUNDATION_STATE="$PRIVATE_DIR/foundation.remote-post-migration.tfstate"
NETWORK_TFVARS="$PRIVATE_DIR/network.live.tfvars"
APPROVED_SHORT="${APPROVED_PLAN_HEAD:0:12}"
APPROVED_REVIEW_DIR="$PRIVATE_DIR/network-plan-review-${APPROVED_SHORT}"
APPROVED_RISK_MD="$APPROVED_REVIEW_DIR/plan-risk-summary.md"
TF_EXE="$(cygpath -u "$LOCALAPPDATA")/Programs/Terraform/1.15.8/terraform.exe"
WORK_DIR="$PRIVATE_DIR/network-apply-${EXPECTED_HEAD:0:12}"
TF_DATA_DIR_UNIX="$WORK_DIR/tfdata"
TF_CLI_CONFIG="$WORK_DIR/terraform.tfrc"
BACKEND_CONFIG="$WORK_DIR/backend.hcl"
EXPECTED_TFVARS="$WORK_DIR/network.expected.tfvars"
PLAN_PATH="$WORK_DIR/network.tfplan"
PLAN_JSON="$WORK_DIR/network-plan.json"
PLAN_LOG="$WORK_DIR/network-plan.log"
APPLY_LOG="$WORK_DIR/network-apply.log"
POST_PLAN_PATH="$WORK_DIR/network-post-apply.tfplan"
POST_PLAN_LOG="$WORK_DIR/network-post-apply-plan.log"
STATE_LIST="$WORK_DIR/network-state-list.txt"
OUTPUTS_JSON="$WORK_DIR/network-outputs.json"
RISK_DIR="$WORK_DIR/risk"
SUMMARY_PATH="$WORK_DIR/network-apply-summary.txt"

[[ -x "$TF_EXE" ]] || fail "TERRAFORM_1_15_8_NOT_FOUND"
[[ -f "$FOUNDATION_TFVARS" ]] || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
[[ -f "$FOUNDATION_STATE" ]] || fail "VERIFIED_FOUNDATION_STATE_NOT_FOUND"
[[ -f "$NETWORK_TFVARS" ]] || fail "PRIVATE_NETWORK_TFVARS_NOT_FOUND"
[[ -f "$NETWORK_EXAMPLE" ]] || fail "NETWORK_TFVARS_EXAMPLE_NOT_FOUND"
[[ -f "$SUMMARIZER" ]] || fail "PLAN_SUMMARIZER_NOT_FOUND"
[[ -f "$APPROVED_RISK_MD" ]] || fail "APPROVED_NETWORK_PLAN_REVIEW_NOT_FOUND"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "UNEXPECTED_CURRENT_BRANCH"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"
git cat-file -e "${APPROVED_PLAN_HEAD}^{commit}" 2>/dev/null || fail "APPROVED_PLAN_COMMIT_NOT_FOUND"
if ! git diff --quiet "$APPROVED_PLAN_HEAD" "$ACTUAL_HEAD" -- infra/terraform/envs/aws-runtime-network; then
  fail "NETWORK_CONFIGURATION_CHANGED_SINCE_APPROVED_PLAN"
fi

gh auth status --hostname github.com >/dev/null 2>&1 || fail "GITHUB_AUTH_UNAVAILABLE"
aws sts get-caller-identity --output json >/dev/null 2>&1 || fail "AWS_IDENTITY_UNAVAILABLE"
EXPECTED_ACCOUNT_ID="$(read_tfvar_string expected_aws_account_id)"
CALLER_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "EXPECTED_ACCOUNT_ID_INVALID"
[[ "$CALLER_ACCOUNT_ID" == "$EXPECTED_ACCOUNT_ID" ]] || fail "AWS_ACCOUNT_MISMATCH"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$TF_DATA_DIR_UNIX" "$RISK_DIR"
cp "$NETWORK_SOURCE"/*.tf "$WORK_DIR/"
cat > "$WORK_DIR/backend.tf" <<'EOF'
terraform {
  backend "s3" {}
}
EOF
cat > "$TF_CLI_CONFIG" <<'EOF'
disable_checkpoint = true
EOF

GITHUB_LOGIN="$(gh api user --jq .login)"
[[ -n "$GITHUB_LOGIN" ]] || fail "GITHUB_LOGIN_UNAVAILABLE"
cp "$NETWORK_EXAMPLE" "$EXPECTED_TFVARS"
sed -i "s/replace-with-owner/${GITHUB_LOGIN}/g" "$EXPECTED_TFVARS"
cmp -s "$EXPECTED_TFVARS" "$NETWORK_TFVARS" || fail "PRIVATE_NETWORK_TFVARS_DRIFT"
grep -Fq 'enable_nat_gateway = true' "$NETWORK_TFVARS" || fail "NETWORK_NAT_BASELINE_MISSING"
grep -Fq 'single_nat_gateway = true' "$NETWORK_TFVARS" || fail "NETWORK_SINGLE_NAT_BASELINE_MISSING"
grep -Fq 'enable_bedrock_runtime_endpoint = false' "$NETWORK_TFVARS" || fail "NETWORK_OPTIONAL_ENDPOINT_GUARD_MISSING"

"${PYTHON_CMD[@]}" - "$FOUNDATION_STATE" "$BACKEND_CONFIG" "$EXPECTED_ACCOUNT_ID" <<'PY'
import json
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
backend_path = Path(sys.argv[2])
expected_account = sys.argv[3]
state = json.loads(state_path.read_text(encoding="utf-8"))
outputs = state.get("outputs", {})

def value(name: str) -> str:
    entry = outputs.get(name)
    if not isinstance(entry, dict) or not isinstance(entry.get("value"), str):
        raise SystemExit(f"FOUNDATION_OUTPUT_INVALID: {name}")
    resolved = entry["value"].strip()
    if not resolved:
        raise SystemExit(f"FOUNDATION_OUTPUT_EMPTY: {name}")
    return resolved

account = value("aws_account_id")
region = value("aws_region")
bucket = value("terraform_state_bucket")
prefix = value("terraform_state_prefix").strip("/")
if account != expected_account:
    raise SystemExit("FOUNDATION_STATE_ACCOUNT_MISMATCH")
if region != "ap-northeast-2":
    raise SystemExit("FOUNDATION_STATE_REGION_MISMATCH")
backend_path.write_text(
    f'bucket       = "{bucket}"\n'
    f'key          = "{prefix}/network/terraform.tfstate"\n'
    f'region       = "{region}"\n'
    'encrypt      = true\n'
    'use_lockfile = true\n',
    encoding="utf-8",
)
PY

TERRAFORM_VERSION="$($TF_EXE version | sed -n '1p')"
[[ "$TERRAFORM_VERSION" == "Terraform v1.15.8" ]] || fail "TERRAFORM_VERSION_MISMATCH: $TERRAFORM_VERSION"

BACKEND_CONFIG_WIN="$(cygpath -am "$BACKEND_CONFIG")"
NETWORK_TFVARS_WIN="$(cygpath -am "$NETWORK_TFVARS")"
PLAN_PATH_WIN="$(cygpath -am "$PLAN_PATH")"
POST_PLAN_PATH_WIN="$(cygpath -am "$POST_PLAN_PATH")"
TF_DATA_DIR_WIN="$(cygpath -am "$TF_DATA_DIR_UNIX")"
TF_CLI_CONFIG_WIN="$(cygpath -am "$TF_CLI_CONFIG")"
WORK_DIR_WIN="$(cygpath -am "$WORK_DIR")"

export TF_DATA_DIR="$TF_DATA_DIR_WIN"
export TF_CLI_CONFIG_FILE="$TF_CLI_CONFIG_WIN"
export TF_IN_AUTOMATION=1
unset TF_PLUGIN_CACHE_DIR || true

"$TF_EXE" -chdir="$WORK_DIR_WIN" init \
  -input=false \
  -reconfigure \
  -backend-config="$BACKEND_CONFIG_WIN"
"$TF_EXE" -chdir="$WORK_DIR_WIN" validate

set +e
"$TF_EXE" -chdir="$WORK_DIR_WIN" plan \
  -input=false \
  -lock-timeout=5m \
  -var-file="$NETWORK_TFVARS_WIN" \
  -out="$PLAN_PATH_WIN" \
  -no-color > "$PLAN_LOG" 2>&1
PLAN_EXIT_CODE=$?
set -e
[[ "$PLAN_EXIT_CODE" -eq 0 ]] || fail "NETWORK_REPLAN_FAILED"

"$TF_EXE" -chdir="$WORK_DIR_WIN" show -json "$PLAN_PATH_WIN" > "$PLAN_JSON"
"${PYTHON_CMD[@]}" "$SUMMARIZER" \
  --plan-json "$PLAN_JSON" \
  --output-dir "$RISK_DIR" \
  --stage network >/dev/null

"${PYTHON_CMD[@]}" - "$APPROVED_RISK_MD" "$PLAN_JSON" <<'PY'
import json
import re
import sys
from pathlib import Path

approved_md = Path(sys.argv[1]).read_text(encoding="utf-8")
plan = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
row_pattern = re.compile(r'^\| `([^`]+)` \| `([^`]+)` \| `([^`]+)` \|$', re.MULTILINE)
approved = {
    (address, resource_type, tuple(action for action in actions.split(",") if action))
    for address, resource_type, actions in row_pattern.findall(approved_md)
}
actual = {
    (
        str(change.get("address", "")),
        str(change.get("type", "")),
        tuple(change.get("change", {}).get("actions", [])),
    )
    for change in plan.get("resource_changes", [])
}
expected_addresses = {
    "aws_eip.nat[0]",
    "aws_internet_gateway.runtime",
    "aws_nat_gateway.runtime[0]",
    "aws_route_table.private[0]",
    "aws_route_table.private[1]",
    "aws_route_table.public",
    "aws_route_table_association.private[0]",
    "aws_route_table_association.private[1]",
    "aws_route_table_association.public[0]",
    "aws_route_table_association.public[1]",
    "aws_subnet.private[0]",
    "aws_subnet.private[1]",
    "aws_subnet.public[0]",
    "aws_subnet.public[1]",
    "aws_vpc.runtime",
    "aws_vpc_endpoint.s3[0]",
}
if approved != actual:
    raise SystemExit("REPLAN_RESOURCE_ACTION_MISMATCH")
if {item[0] for item in actual} != expected_addresses:
    raise SystemExit("REPLAN_EXPECTED_ADDRESS_SET_MISMATCH")
if any(actions != ("create",) for _, _, actions in actual):
    raise SystemExit("REPLAN_NON_CREATE_ACTION_PRESENT")
if len(actual) != 16:
    raise SystemExit("REPLAN_RESOURCE_COUNT_MISMATCH")
print("ApprovedResourceActionMatch=true")
print("ApprovedResourceCount=16")
PY

grep -Fqx 'terraform_plan_risk_gate=passed' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_RISK_GATE_FAILED"
grep -Fqx 'destructive_resource_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_DESTRUCTIVE_CHANGE_PRESENT"
grep -Fqx 'replacement_resource_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_REPLACEMENT_PRESENT"
grep -Fqx 'public_exposure_finding_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_PUBLIC_EXPOSURE_PRESENT"
grep -Fqx 'optional_adapter_resource_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_OPTIONAL_ADAPTER_PRESENT"
grep -Fqx 'high_cost_resource_count=1' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_HIGH_COST_COUNT_MISMATCH"

sha256sum "$PLAN_PATH" > "$WORK_DIR/network.tfplan.sha256"
printf '%s\n' \
  "NetworkApplyStarted=true" \
  "ApprovedPlanHead=${APPROVED_SHORT}" \
  "ApprovedResourceActionMatch=true" \
  "ApprovedResourceCount=16" \
  "TerraformDestroyExecuted=false"

set +e
"$TF_EXE" -chdir="$WORK_DIR_WIN" apply \
  -input=false \
  -no-color \
  "$PLAN_PATH_WIN" > "$APPLY_LOG" 2>&1
APPLY_EXIT_CODE=$?
set -e
if [[ "$APPLY_EXIT_CODE" -ne 0 ]]; then
  printf '%s\n' \
    "NetworkApplyStatus=failed-or-partial" \
    "DoNotRerunAutomatically=true" \
    "TerraformDestroyExecuted=false" \
    "PrivateApplyLogCreated=true" >&2
  exit "$APPLY_EXIT_CODE"
fi

"$TF_EXE" -chdir="$WORK_DIR_WIN" state list > "$STATE_LIST"
MANAGED_STATE_COUNT="$(grep -v '^data\.' "$STATE_LIST" | grep -c . || true)"
[[ "$MANAGED_STATE_COUNT" == "16" ]] || fail "NETWORK_MANAGED_STATE_COUNT_MISMATCH"
[[ "$(grep -c '^aws_nat_gateway\.runtime\[0\]$' "$STATE_LIST" || true)" == "1" ]] || fail "NETWORK_NAT_GATEWAY_STATE_MISMATCH"
[[ "$(grep -c '^aws_subnet\.public\[' "$STATE_LIST" || true)" == "2" ]] || fail "NETWORK_PUBLIC_SUBNET_STATE_MISMATCH"
[[ "$(grep -c '^aws_subnet\.private\[' "$STATE_LIST" || true)" == "2" ]] || fail "NETWORK_PRIVATE_SUBNET_STATE_MISMATCH"
[[ "$(grep -c '^aws_vpc_endpoint\.s3\[0\]$' "$STATE_LIST" || true)" == "1" ]] || fail "NETWORK_S3_ENDPOINT_STATE_MISMATCH"

"$TF_EXE" -chdir="$WORK_DIR_WIN" output -json > "$OUTPUTS_JSON"
"${PYTHON_CMD[@]}" - "$OUTPUTS_JSON" <<'PY'
import json
import sys
from pathlib import Path

outputs = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
required_strings = ("vpc_id", "vpc_cidr_block", "s3_gateway_endpoint_id")
for name in required_strings:
    value = outputs.get(name, {}).get("value")
    if not isinstance(value, str) or not value:
        raise SystemExit(f"NETWORK_OUTPUT_INVALID: {name}")
for name in ("public_subnet_ids", "private_subnet_ids", "private_subnet_cidr_blocks", "private_route_table_ids"):
    value = outputs.get(name, {}).get("value")
    if not isinstance(value, list) or len(value) != 2 or not all(isinstance(item, str) and item for item in value):
        raise SystemExit(f"NETWORK_OUTPUT_INVALID: {name}")
if outputs.get("bedrock_runtime_endpoint_dns_name", {}).get("value") is not None:
    raise SystemExit("OPTIONAL_BEDROCK_ENDPOINT_UNEXPECTEDLY_ENABLED")
PY

set +e
"$TF_EXE" -chdir="$WORK_DIR_WIN" plan \
  -input=false \
  -lock-timeout=5m \
  -detailed-exitcode \
  -var-file="$NETWORK_TFVARS_WIN" \
  -out="$POST_PLAN_PATH_WIN" \
  -no-color > "$POST_PLAN_LOG" 2>&1
POST_PLAN_EXIT_CODE=$?
set -e
[[ "$POST_PLAN_EXIT_CODE" -eq 0 ]] || fail "POST_APPLY_PLAN_NOT_EMPTY"

STATE_BUCKET="$(sed -nE 's/^[[:space:]]*bucket[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p' "$BACKEND_CONFIG" | head -n 1)"
STATE_KEY="$(sed -nE 's/^[[:space:]]*key[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p' "$BACKEND_CONFIG" | head -n 1)"
[[ -n "$STATE_BUCKET" && -n "$STATE_KEY" ]] || fail "NETWORK_BACKEND_VALUES_MISSING"
if aws s3api head-object --bucket "$STATE_BUCKET" --key "${STATE_KEY}.tflock" >/dev/null 2>&1; then
  fail "STALE_NETWORK_LOCK_OBJECT_PRESENT"
fi
aws s3api head-object --bucket "$STATE_BUCKET" --key "$STATE_KEY" >/dev/null 2>&1 || fail "NETWORK_REMOTE_STATE_OBJECT_MISSING"

rm -f "$PLAN_JSON" "$PLAN_PATH" "$POST_PLAN_PATH" "$EXPECTED_TFVARS"

cat > "$SUMMARY_PATH" <<EOF
NetworkApplyStatus=success
RepositoryHead=${ACTUAL_HEAD:0:12}
ApprovedPlanHead=${APPROVED_SHORT}
PythonCommand=${PYTHON_LABEL}
ApprovedResourceActionMatch=true
CreatedResourceCount=16
ManagedStateResourceCount=16
NatGatewayCount=1
PublicSubnetCount=2
PrivateSubnetCount=2
S3GatewayEndpointCount=1
OptionalBedrockEndpointEnabled=false
PostApplyPlanNoChanges=true
RemoteStateObjectPresent=true
StaleLockObjectPresent=false
TerraformApplyExecuted=true
TerraformDestroyExecuted=false
GitHubMutation=none
AwsMutation=network-16-create
PrivateEvidenceDirectoryCreated=true
EOF
cat "$SUMMARY_PATH"
