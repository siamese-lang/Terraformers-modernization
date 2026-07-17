#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/apply-approved-runtime-dependencies.sh \
    --expected-head CURRENT_SHA \
    --approved-plan-head PLAN_SHA

The command rebuilds the runtime-dependencies plan with local AWS credentials,
requires the exact reviewed 13-resource create set, applies that saved plan once,
and verifies remote state and a no-change post-apply plan. It never runs
terraform destroy and never writes a Secrets Manager secret value.
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

for command_name in git gh aws cygpath sed grep head rm mkdir cp cmp sha256sum; do
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
STAGE="runtime-dependencies"
RUNTIME_SOURCE="$REPO_ROOT/infra/terraform/envs/backend-runtime-dependencies"
SUMMARIZER="$REPO_ROOT/scripts/deploy/summarize-terraform-plan.py"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
FOUNDATION_TFVARS="$PRIVATE_DIR/foundation.tfvars"
FOUNDATION_STATE="$PRIVATE_DIR/foundation.remote-post-migration.tfstate"
RUNTIME_TFVARS="$PRIVATE_DIR/runtime-dependencies.live.tfvars"
APPROVED_SHORT="${APPROVED_PLAN_HEAD:0:12}"
APPROVED_REVIEW_DIR="$PRIVATE_DIR/runtime-dependencies-plan-review-${APPROVED_SHORT}"
APPROVED_RISK_MD="$APPROVED_REVIEW_DIR/plan-risk-summary.md"
TF_EXE="$(cygpath -u "$LOCALAPPDATA")/Programs/Terraform/1.15.8/terraform.exe"
WORK_DIR="$PRIVATE_DIR/runtime-dependencies-apply-${EXPECTED_HEAD:0:12}"
TF_DATA_DIR_UNIX="$WORK_DIR/tfdata"
TF_CLI_CONFIG="$WORK_DIR/terraform.tfrc"
BACKEND_CONFIG="$WORK_DIR/backend.hcl"
PLAN_PATH="$WORK_DIR/runtime-dependencies.tfplan"
PLAN_JSON="$WORK_DIR/runtime-dependencies-plan.json"
PLAN_LOG="$WORK_DIR/runtime-dependencies-plan.log"
APPLY_LOG="$WORK_DIR/runtime-dependencies-apply.log"
POST_PLAN_PATH="$WORK_DIR/runtime-dependencies-post-apply.tfplan"
POST_PLAN_LOG="$WORK_DIR/runtime-dependencies-post-apply-plan.log"
STATE_LIST="$WORK_DIR/runtime-dependencies-state-list.txt"
OUTPUTS_JSON="$WORK_DIR/runtime-dependencies-outputs.json"
RISK_DIR="$WORK_DIR/risk"
SUMMARY_PATH="$WORK_DIR/runtime-dependencies-apply-summary.txt"

[[ -x "$TF_EXE" ]] || fail "TERRAFORM_1_15_8_NOT_FOUND"
[[ -f "$FOUNDATION_TFVARS" ]] || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
[[ -f "$FOUNDATION_STATE" ]] || fail "VERIFIED_FOUNDATION_STATE_NOT_FOUND"
[[ -f "$RUNTIME_TFVARS" ]] || fail "PRIVATE_RUNTIME_DEPENDENCIES_TFVARS_NOT_FOUND"
[[ -f "$SUMMARIZER" ]] || fail "PLAN_SUMMARIZER_NOT_FOUND"
[[ -f "$APPROVED_RISK_MD" ]] || fail "APPROVED_RUNTIME_DEPENDENCIES_PLAN_REVIEW_NOT_FOUND"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "UNEXPECTED_CURRENT_BRANCH"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"
git cat-file -e "${APPROVED_PLAN_HEAD}^{commit}" 2>/dev/null || fail "APPROVED_PLAN_COMMIT_NOT_FOUND"
if ! git diff --quiet "$APPROVED_PLAN_HEAD" "$ACTUAL_HEAD" -- infra/terraform/envs/backend-runtime-dependencies; then
  fail "RUNTIME_DEPENDENCIES_CONFIGURATION_CHANGED_SINCE_APPROVED_PLAN"
fi

gh auth status --hostname github.com >/dev/null 2>&1 || fail "GITHUB_AUTH_UNAVAILABLE"
aws sts get-caller-identity --output json >/dev/null 2>&1 || fail "AWS_IDENTITY_UNAVAILABLE"
EXPECTED_ACCOUNT_ID="$(read_tfvar_string expected_aws_account_id)"
CALLER_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "EXPECTED_ACCOUNT_ID_INVALID"
[[ "$CALLER_ACCOUNT_ID" == "$EXPECTED_ACCOUNT_ID" ]] || fail "AWS_ACCOUNT_MISMATCH"

if grep -Eq 'replace-with|000000000000|0\.0\.0\.0/0|::/0' "$RUNTIME_TFVARS"; then
  fail "RUNTIME_TFVARS_PLACEHOLDER_OR_UNSAFE_VALUE_PRESENT"
fi
grep -Fq 'backend_ecr_repository_name = "terraformers-backend"' "$RUNTIME_TFVARS" || fail "RUNTIME_ECR_NAME_DRIFT"
grep -Fq 'runtime_secret_name        = "terraformers/dev/backend/runtime"' "$RUNTIME_TFVARS" || fail "RUNTIME_SECRET_NAME_DRIFT"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$TF_DATA_DIR_UNIX" "$RISK_DIR"
cp "$RUNTIME_SOURCE"/*.tf "$WORK_DIR/"
cat > "$WORK_DIR/backend.tf" <<'EOF'
terraform {
  backend "s3" {}
}
EOF
cat > "$TF_CLI_CONFIG" <<'EOF'
disable_checkpoint = true
EOF

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
    f'key          = "{prefix}/runtime-dependencies/terraform.tfstate"\n'
    f'region       = "{region}"\n'
    'encrypt      = true\n'
    'use_lockfile = true\n',
    encoding="utf-8",
)
PY

TERRAFORM_VERSION="$($TF_EXE version | sed -n '1p')"
[[ "$TERRAFORM_VERSION" == "Terraform v1.15.8" ]] || fail "TERRAFORM_VERSION_MISMATCH: $TERRAFORM_VERSION"

BACKEND_CONFIG_WIN="$(cygpath -am "$BACKEND_CONFIG")"
RUNTIME_TFVARS_WIN="$(cygpath -am "$RUNTIME_TFVARS")"
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
  -var-file="$RUNTIME_TFVARS_WIN" \
  -out="$PLAN_PATH_WIN" \
  -no-color > "$PLAN_LOG" 2>&1
PLAN_EXIT_CODE=$?
set -e
[[ "$PLAN_EXIT_CODE" -eq 0 ]] || fail "RUNTIME_DEPENDENCIES_REPLAN_FAILED"

"$TF_EXE" -chdir="$WORK_DIR_WIN" show -json "$PLAN_PATH_WIN" > "$PLAN_JSON"
"${PYTHON_CMD[@]}" "$SUMMARIZER" \
  --plan-json "$PLAN_JSON" \
  --output-dir "$RISK_DIR" \
  --stage runtime-dependencies >/dev/null

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
expected_types = {
    "aws_ecr_lifecycle_policy.backend": "aws_ecr_lifecycle_policy",
    "aws_ecr_repository.backend": "aws_ecr_repository",
    "aws_s3_bucket.uploads": "aws_s3_bucket",
    "aws_s3_bucket.results": "aws_s3_bucket",
    "aws_s3_bucket_public_access_block.uploads": "aws_s3_bucket_public_access_block",
    "aws_s3_bucket_public_access_block.results": "aws_s3_bucket_public_access_block",
    "aws_s3_bucket_server_side_encryption_configuration.uploads": "aws_s3_bucket_server_side_encryption_configuration",
    "aws_s3_bucket_server_side_encryption_configuration.results": "aws_s3_bucket_server_side_encryption_configuration",
    "aws_s3_bucket_versioning.uploads": "aws_s3_bucket_versioning",
    "aws_s3_bucket_versioning.results": "aws_s3_bucket_versioning",
    "aws_secretsmanager_secret.backend_runtime": "aws_secretsmanager_secret",
    "aws_sqs_queue.ai_log": "aws_sqs_queue",
    "aws_sqs_queue.terraform_log": "aws_sqs_queue",
}
expected = {(address, resource_type, ("create",)) for address, resource_type in expected_types.items()}
if approved != actual:
    raise SystemExit("REPLAN_RESOURCE_ACTION_MISMATCH")
if actual != expected:
    raise SystemExit("REPLAN_EXPECTED_RESOURCE_SET_MISMATCH")
if len(actual) != 13:
    raise SystemExit("REPLAN_RESOURCE_COUNT_MISMATCH")
print("ApprovedResourceActionMatch=true")
print("ApprovedResourceCount=13")
PY

grep -Fqx 'terraform_plan_risk_gate=passed' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_RISK_GATE_FAILED"
grep -Fqx 'resource_change_count=13' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_RESOURCE_COUNT_MISMATCH"
grep -Fqx 'destructive_resource_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_DESTRUCTIVE_CHANGE_PRESENT"
grep -Fqx 'replacement_resource_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_REPLACEMENT_PRESENT"
grep -Fqx 'public_exposure_finding_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_PUBLIC_EXPOSURE_PRESENT"
grep -Fqx 'optional_adapter_resource_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_OPTIONAL_ADAPTER_PRESENT"
grep -Fqx 'high_cost_resource_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_HIGH_COST_COUNT_MISMATCH"

sha256sum "$PLAN_PATH" > "$WORK_DIR/runtime-dependencies.tfplan.sha256"
printf '%s\n' \
  "RuntimeDependenciesApplyStarted=true" \
  "ApprovedPlanHead=${APPROVED_SHORT}" \
  "ApprovedResourceActionMatch=true" \
  "ApprovedResourceCount=13" \
  "SecretValueWriteExecuted=false" \
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
    "RuntimeDependenciesApplyStatus=failed-or-partial" \
    "DoNotRerunAutomatically=true" \
    "SecretValueWriteExecuted=false" \
    "TerraformDestroyExecuted=false" \
    "PrivateApplyLogCreated=true" >&2
  exit "$APPLY_EXIT_CODE"
fi

"$TF_EXE" -chdir="$WORK_DIR_WIN" state list > "$STATE_LIST"
MANAGED_STATE_COUNT="$(grep -v '^data\.' "$STATE_LIST" | grep -c . || true)"
[[ "$MANAGED_STATE_COUNT" == "13" ]] || fail "RUNTIME_DEPENDENCIES_MANAGED_STATE_COUNT_MISMATCH"
for address in \
  aws_ecr_lifecycle_policy.backend \
  aws_ecr_repository.backend \
  aws_s3_bucket.results \
  aws_s3_bucket.uploads \
  aws_s3_bucket_public_access_block.results \
  aws_s3_bucket_public_access_block.uploads \
  aws_s3_bucket_server_side_encryption_configuration.results \
  aws_s3_bucket_server_side_encryption_configuration.uploads \
  aws_s3_bucket_versioning.results \
  aws_s3_bucket_versioning.uploads \
  aws_secretsmanager_secret.backend_runtime \
  aws_sqs_queue.ai_log \
  aws_sqs_queue.terraform_log; do
  grep -Fqx "$address" "$STATE_LIST" || fail "RUNTIME_DEPENDENCIES_STATE_ADDRESS_MISSING"
done

"$TF_EXE" -chdir="$WORK_DIR_WIN" output -json > "$OUTPUTS_JSON"
"${PYTHON_CMD[@]}" - "$OUTPUTS_JSON" <<'PY'
import json
import sys
from pathlib import Path

outputs = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
required_strings = (
    "backend_image_repository_url",
    "upload_bucket_name",
    "upload_bucket_arn",
    "result_bucket_name",
    "result_bucket_arn",
    "analysis_result_key_prefix",
    "ai_log_queue_url",
    "ai_log_queue_arn",
    "terraform_log_queue_url",
    "terraform_log_queue_arn",
    "backend_runtime_secret_arn",
    "kubernetes_runtime_secret_name",
)
for name in required_strings:
    value = outputs.get(name, {}).get("value")
    if not isinstance(value, str) or not value:
        raise SystemExit(f"RUNTIME_DEPENDENCIES_OUTPUT_INVALID: {name}")
required_runtime_values = outputs.get("next_required_runtime_values", {}).get("value")
expected_runtime_values = {
    "SPRING_DATASOURCE_URL",
    "SPRING_DATASOURCE_USERNAME",
    "SPRING_DATASOURCE_PASSWORD",
    "COGNITO_REGION",
    "COGNITO_USER_POOL_ID",
    "COGNITO_USER_POOL_CLIENT_ID",
    "COGNITO_JWKS_URL",
}
if not isinstance(required_runtime_values, list) or set(required_runtime_values) != expected_runtime_values:
    raise SystemExit("NEXT_REQUIRED_RUNTIME_VALUES_MISMATCH")
PY

ECR_NAME="$(sed -nE 's/^[[:space:]]*backend_ecr_repository_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$RUNTIME_TFVARS" | head -n 1)"
UPLOAD_BUCKET="$(sed -nE 's/^[[:space:]]*upload_bucket_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$RUNTIME_TFVARS" | head -n 1)"
RESULT_BUCKET="$(sed -nE 's/^[[:space:]]*result_bucket_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$RUNTIME_TFVARS" | head -n 1)"
RUNTIME_SECRET_NAME="$(sed -nE 's/^[[:space:]]*runtime_secret_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$RUNTIME_TFVARS" | head -n 1)"
[[ -n "$ECR_NAME" && -n "$UPLOAD_BUCKET" && -n "$RESULT_BUCKET" && -n "$RUNTIME_SECRET_NAME" ]] || fail "RUNTIME_RESOURCE_NAMES_MISSING"

[[ "$(aws ecr describe-repositories --repository-names "$ECR_NAME" --query 'repositories[0].imageTagMutability' --output text)" == "IMMUTABLE" ]] || fail "ECR_IMMUTABILITY_VERIFICATION_FAILED"
[[ "$(aws ecr describe-repositories --repository-names "$ECR_NAME" --query 'repositories[0].imageScanningConfiguration.scanOnPush' --output text)" == "True" ]] || fail "ECR_SCAN_ON_PUSH_VERIFICATION_FAILED"
for bucket in "$UPLOAD_BUCKET" "$RESULT_BUCKET"; do
  [[ "$(aws s3api get-bucket-versioning --bucket "$bucket" --query Status --output text)" == "Enabled" ]] || fail "S3_VERSIONING_VERIFICATION_FAILED"
  [[ "$(aws s3api get-public-access-block --bucket "$bucket" --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' --output text)" == $'True\tTrue\tTrue\tTrue' ]] || fail "S3_PUBLIC_ACCESS_BLOCK_VERIFICATION_FAILED"
  [[ "$(aws s3api get-bucket-encryption --bucket "$bucket" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)" == "AES256" ]] || fail "S3_ENCRYPTION_VERIFICATION_FAILED"
done
aws secretsmanager describe-secret --secret-id "$RUNTIME_SECRET_NAME" >/dev/null 2>&1 || fail "RUNTIME_SECRET_CONTAINER_VERIFICATION_FAILED"

set +e
"$TF_EXE" -chdir="$WORK_DIR_WIN" plan \
  -input=false \
  -lock-timeout=5m \
  -detailed-exitcode \
  -var-file="$RUNTIME_TFVARS_WIN" \
  -out="$POST_PLAN_PATH_WIN" \
  -no-color > "$POST_PLAN_LOG" 2>&1
POST_PLAN_EXIT_CODE=$?
set -e
[[ "$POST_PLAN_EXIT_CODE" -eq 0 ]] || fail "POST_APPLY_PLAN_NOT_EMPTY"

STATE_BUCKET="$(sed -nE 's/^[[:space:]]*bucket[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$BACKEND_CONFIG" | head -n 1)"
STATE_KEY="$(sed -nE 's/^[[:space:]]*key[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$BACKEND_CONFIG" | head -n 1)"
[[ -n "$STATE_BUCKET" && -n "$STATE_KEY" ]] || fail "RUNTIME_DEPENDENCIES_BACKEND_VALUES_MISSING"
if aws s3api head-object --bucket "$STATE_BUCKET" --key "${STATE_KEY}.tflock" >/dev/null 2>&1; then
  fail "STALE_RUNTIME_DEPENDENCIES_LOCK_OBJECT_PRESENT"
fi
aws s3api head-object --bucket "$STATE_BUCKET" --key "$STATE_KEY" >/dev/null 2>&1 || fail "RUNTIME_DEPENDENCIES_REMOTE_STATE_OBJECT_MISSING"

rm -f "$PLAN_JSON" "$PLAN_PATH" "$POST_PLAN_PATH"

cat > "$SUMMARY_PATH" <<EOF
RuntimeDependenciesApplyStatus=success
RepositoryHead=${ACTUAL_HEAD:0:12}
ApprovedPlanHead=${APPROVED_SHORT}
PythonCommand=${PYTHON_LABEL}
ApprovedResourceActionMatch=true
CreatedResourceCount=13
ManagedStateResourceCount=13
EcrRepositoryCount=1
EcrLifecyclePolicyCount=1
S3BucketCount=2
S3PublicAccessBlockCount=2
S3VersioningCount=2
S3EncryptionConfigurationCount=2
SqsQueueCount=2
SecretsManagerContainerCount=1
SecretValueWriteExecuted=false
PostApplyPlanNoChanges=true
RemoteStateObjectPresent=true
StaleLockObjectPresent=false
TerraformApplyExecuted=true
TerraformDestroyExecuted=false
GitHubMutation=none
AwsMutation=runtime-dependencies-13-create
PrivateEvidenceDirectoryCreated=true
EOF
cat "$SUMMARY_PATH"
