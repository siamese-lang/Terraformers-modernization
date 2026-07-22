#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/prepare-and-dispatch-runtime-dependencies-plan.sh \
    --expected-head SHA

The command verifies that the live network stage is complete, checks for
unmanaged name collisions, creates private runtime-dependencies tfvars outside
the repository, sets only AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64 in the
aws-live-plan environment, runs the strict stage prerequisite inventory, and
dispatches the guarded pre-merge plan. It performs no Terraform apply/destroy.
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

for command_name in git gh aws cygpath sed grep head cp sleep; do
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
NETWORK_APPLY_ROOT="$PRIVATE_DIR/network-apply-"
RUNTIME_APPLY_ROOT="$PRIVATE_DIR/runtime-dependencies-apply-"
RUNTIME_EXAMPLE="$REPO_ROOT/infra/terraform/envs/backend-runtime-dependencies/live.tfvars.example"
RUNTIME_TFVARS="$PRIVATE_DIR/runtime-dependencies.live.tfvars"

[[ -f "$FOUNDATION_TFVARS" ]] || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
[[ -f "$FOUNDATION_STATE" ]] || fail "VERIFIED_FOUNDATION_STATE_NOT_FOUND"
[[ -f "$RUNTIME_EXAMPLE" ]] || fail "RUNTIME_DEPENDENCIES_TFVARS_EXAMPLE_NOT_FOUND"

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

NETWORK_SUMMARY="$(find "$PRIVATE_DIR" -maxdepth 2 -type f -path "${NETWORK_APPLY_ROOT}*/network-apply-summary.txt" -print 2>/dev/null | sort | tail -n 1)"
[[ -f "$NETWORK_SUMMARY" ]] || fail "SUCCESSFUL_NETWORK_APPLY_EVIDENCE_NOT_FOUND"
grep -Fqx 'NetworkApplyStatus=success' "$NETWORK_SUMMARY" || fail "NETWORK_APPLY_NOT_SUCCESSFUL"
grep -Fqx 'CreatedResourceCount=16' "$NETWORK_SUMMARY" || fail "NETWORK_RESOURCE_COUNT_MISMATCH"
grep -Fqx 'PostApplyPlanNoChanges=true' "$NETWORK_SUMMARY" || fail "NETWORK_POST_APPLY_DRIFT_PRESENT"
grep -Fqx 'RemoteStateObjectPresent=true' "$NETWORK_SUMMARY" || fail "NETWORK_REMOTE_STATE_MISSING"

RUNTIME_SUMMARY="$(
  find "$PRIVATE_DIR" \
    -maxdepth 2 \
    -type f \
    -path "${RUNTIME_APPLY_ROOT}*/runtime-dependencies-apply-summary.txt" \
    -print 2>/dev/null |
  sort |
  tail -n 1
)"

BASE_RUNTIME_APPLIED=false
if [[ -n "$RUNTIME_SUMMARY" ]]; then
  [[ -f "$RUNTIME_SUMMARY" ]] || fail "RUNTIME_APPLY_SUMMARY_NOT_FOUND"
  grep -Fqx 'RuntimeDependenciesApplyStatus=success' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_APPLY_NOT_SUCCESSFUL"
  grep -Fqx 'CreatedResourceCount=13' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_CREATED_RESOURCE_COUNT_MISMATCH"
  grep -Fqx 'ManagedStateResourceCount=13' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_MANAGED_STATE_COUNT_MISMATCH"
  grep -Fqx 'EcrRepositoryCount=1' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_ECR_COUNT_MISMATCH"
  grep -Fqx 'S3BucketCount=2' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_S3_COUNT_MISMATCH"
  grep -Fqx 'SqsQueueCount=2' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_SQS_COUNT_MISMATCH"
  grep -Fqx 'SecretsManagerContainerCount=1' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_SECRET_COUNT_MISMATCH"
  grep -Fqx 'SecretValueWriteExecuted=false' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_SECRET_VALUE_WRITE_PRESENT"
  grep -Fqx 'PostApplyPlanNoChanges=true' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_POST_APPLY_DRIFT_PRESENT"
  grep -Fqx 'RemoteStateObjectPresent=true' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_REMOTE_STATE_MISSING"
  grep -Fqx 'TerraformDestroyExecuted=false' "$RUNTIME_SUMMARY" || fail "RUNTIME_BASE_DESTROY_EXECUTED"
  BASE_RUNTIME_APPLIED=true
fi

GITHUB_LOGIN="$(gh api user --jq .login)"
[[ -n "$GITHUB_LOGIN" ]] || fail "GITHUB_LOGIN_UNAVAILABLE"

GITHUB_OIDC_PROVIDER_ARN="$("${PYTHON_CMD[@]}" - "$FOUNDATION_STATE" "$EXPECTED_ACCOUNT_ID" <<'PYCODE'
import json
import re
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
expected_account = sys.argv[2]
state = json.loads(state_path.read_text(encoding="utf-8"))

entry = state.get("outputs", {}).get("github_oidc_provider_arn")
if not isinstance(entry, dict) or not isinstance(entry.get("value"), str):
    raise SystemExit(
        "FOUNDATION_GITHUB_OIDC_PROVIDER_ARN_OUTPUT_INVALID"
    )

arn = entry["value"].strip()
pattern = (
    r"^arn:aws[a-zA-Z-]*:iam::([0-9]{12}):"
    r"oidc-provider/token\.actions\.githubusercontent\.com$"
)
match = re.fullmatch(pattern, arn)

if match is None:
    raise SystemExit(
        "FOUNDATION_GITHUB_OIDC_PROVIDER_ARN_INVALID"
    )

if match.group(1) != expected_account:
    raise SystemExit(
        "FOUNDATION_GITHUB_OIDC_PROVIDER_ARN_ACCOUNT_MISMATCH"
    )

print(arn)
PYCODE
)"

UPLOAD_BUCKET="terraformers-dev-upload-${EXPECTED_ACCOUNT_ID}"
RESULT_BUCKET="terraformers-dev-result-${EXPECTED_ACCOUNT_ID}"

cp "$RUNTIME_EXAMPLE" "$RUNTIME_TFVARS"
sed -i \
  -e "s/replace-with-unique-terraformers-upload-bucket/${UPLOAD_BUCKET}/g" \
  -e "s/replace-with-unique-terraformers-result-bucket/${RESULT_BUCKET}/g" \
  -e "s|arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com|${GITHUB_OIDC_PROVIDER_ARN}|g" \
  -e "s/replace-with-owner/${GITHUB_LOGIN}/g" \
  "$RUNTIME_TFVARS"

if grep -Eq 'replace-with|000000000000|0\.0\.0\.0/0|::/0' "$RUNTIME_TFVARS"; then
  fail "RUNTIME_TFVARS_PLACEHOLDER_OR_UNSAFE_VALUE_PRESENT"
fi
grep -Fq 'backend_ecr_repository_name = "terraformers-backend"' "$RUNTIME_TFVARS" || fail "RUNTIME_ECR_NAME_DRIFT"
grep -Fq 'runtime_secret_name        = "terraformers/dev/backend/runtime"' "$RUNTIME_TFVARS" || fail "RUNTIME_SECRET_NAME_DRIFT"

check_absent() {
  local code="$1"
  shift
  set +e
  "$@" >/dev/null 2>&1
  local result=$?
  set -e
  [[ "$result" -ne 0 ]] || fail "$code"
}

check_bucket_available() {
  local bucket="$1"
  local output
  local result
  set +e
  output="$(aws s3api head-bucket --bucket "$bucket" 2>&1)"
  result=$?
  set -e
  if [[ "$result" -eq 0 ]]; then
    fail "UNMANAGED_S3_BUCKET_ALREADY_EXISTS"
  fi
  if grep -Eqi '\(403\)|Forbidden|AccessDenied' <<< "$output"; then
    fail "S3_BUCKET_NAME_NOT_AVAILABLE"
  fi
  if ! grep -Eqi '\(404\)|Not Found|NoSuchBucket' <<< "$output"; then
    fail "S3_BUCKET_AVAILABILITY_CHECK_INCONCLUSIVE"
  fi
}

verify_initial_resource_absence() {
  check_absent "UNMANAGED_ECR_REPOSITORY_ALREADY_EXISTS" \
    aws ecr describe-repositories \
      --repository-names terraformers-backend

  check_absent "UNMANAGED_AI_LOG_QUEUE_ALREADY_EXISTS" \
    aws sqs get-queue-url \
      --queue-name terraformers-ai-log

  check_absent "UNMANAGED_TERRAFORM_LOG_QUEUE_ALREADY_EXISTS" \
    aws sqs get-queue-url \
      --queue-name terraformers-terraform-log

  check_absent "UNMANAGED_RUNTIME_SECRET_ALREADY_EXISTS" \
    aws secretsmanager describe-secret \
      --secret-id terraformers/dev/backend/runtime

  check_bucket_available "$UPLOAD_BUCKET"
  check_bucket_available "$RESULT_BUCKET"
}

verify_managed_base_runtime() {
  local ecr_state
  local ai_queue_url
  local terraform_queue_url
  local runtime_secret_name
  local runtime_secret_arn
  local bucket
  local bucket_region

  ecr_state="$(
    aws ecr describe-repositories \
      --repository-names terraformers-backend \
      --query 'repositories[0].[repositoryName,imageTagMutability,imageScanningConfiguration.scanOnPush]' \
      --output text
  )"
  [[ "$ecr_state" == $'terraformers-backend\tIMMUTABLE\tTrue' ]] ||
    fail "MANAGED_ECR_REPOSITORY_CONTRACT_MISMATCH"

  aws ecr get-lifecycle-policy \
    --repository-name terraformers-backend \
    >/dev/null 2>&1 ||
    fail "MANAGED_ECR_LIFECYCLE_POLICY_MISSING"

  ai_queue_url="$(
    aws sqs get-queue-url \
      --queue-name terraformers-ai-log \
      --query QueueUrl \
      --output text
  )"
  [[ "$ai_queue_url" == "https://sqs.ap-northeast-2.amazonaws.com/${EXPECTED_ACCOUNT_ID}/terraformers-ai-log" ]] ||
    fail "MANAGED_AI_LOG_QUEUE_URL_MISMATCH"

  terraform_queue_url="$(
    aws sqs get-queue-url \
      --queue-name terraformers-terraform-log \
      --query QueueUrl \
      --output text
  )"
  [[ "$terraform_queue_url" == "https://sqs.ap-northeast-2.amazonaws.com/${EXPECTED_ACCOUNT_ID}/terraformers-terraform-log" ]] ||
    fail "MANAGED_TERRAFORM_LOG_QUEUE_URL_MISMATCH"

  runtime_secret_name="$(
    aws secretsmanager describe-secret \
      --secret-id terraformers/dev/backend/runtime \
      --query Name \
      --output text
  )"
  [[ "$runtime_secret_name" == "terraformers/dev/backend/runtime" ]] ||
    fail "MANAGED_RUNTIME_SECRET_NAME_MISMATCH"

  runtime_secret_arn="$(
    aws secretsmanager describe-secret \
      --secret-id terraformers/dev/backend/runtime \
      --query ARN \
      --output text
  )"
  [[ "$runtime_secret_arn" =~ ^arn:aws[a-zA-Z-]*:secretsmanager:ap-northeast-2:${EXPECTED_ACCOUNT_ID}:secret:terraformers/dev/backend/runtime-[A-Za-z0-9]+$ ]] ||
    fail "MANAGED_RUNTIME_SECRET_ARN_MISMATCH"

  for bucket in "$UPLOAD_BUCKET" "$RESULT_BUCKET"; do
    aws s3api head-bucket \
      --bucket "$bucket" \
      >/dev/null 2>&1 ||
      fail "MANAGED_S3_BUCKET_MISSING"

    bucket_region="$(
      aws s3api get-bucket-location \
        --bucket "$bucket" \
        --query LocationConstraint \
        --output text
    )"
    [[ "$bucket_region" == "ap-northeast-2" ]] ||
      fail "MANAGED_S3_BUCKET_REGION_MISMATCH"

    [[ "$(
      aws s3api get-bucket-versioning \
        --bucket "$bucket" \
        --query Status \
        --output text
    )" == "Enabled" ]] ||
      fail "MANAGED_S3_VERSIONING_MISMATCH"

    [[ "$(
      aws s3api get-public-access-block \
        --bucket "$bucket" \
        --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' \
        --output text
    )" == $'True\tTrue\tTrue\tTrue' ]] ||
      fail "MANAGED_S3_PUBLIC_ACCESS_BLOCK_MISMATCH"

    [[ "$(
      aws s3api get-bucket-encryption \
        --bucket "$bucket" \
        --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
        --output text
    )" == "AES256" ]] ||
      fail "MANAGED_S3_ENCRYPTION_MISMATCH"
  done
}

if [[ "$BASE_RUNTIME_APPLIED" == "true" ]]; then
  verify_managed_base_runtime
  EXISTING_RESOURCE_MODE="managed-base-13"
else
  verify_initial_resource_absence
  EXISTING_RESOURCE_MODE="absent-initial"
fi

"${PYTHON_CMD[@]}" - "$RUNTIME_TFVARS" <<'PY' |
import base64
import sys
from pathlib import Path
sys.stdout.write(base64.b64encode(Path(sys.argv[1]).read_bytes()).decode("ascii"))
PY
  gh secret set AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64 \
    --env "$ENVIRONMENT" \
    --repo "$REPO"

bash scripts/deploy/inventory-live-aws-prerequisites.sh \
  --expected-head "$EXPECTED_HEAD" \
  --stage runtime-dependencies \
  --strict

gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref "$BRANCH" \
  -f execute_live_plan=true \
  -f plan_stage=runtime-dependencies \
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
[[ -n "$RUN_RECORD" ]] || fail "DISPATCHED_RUNTIME_PLAN_RUN_NOT_FOUND"

IFS=$'\t' read -r RUN_ID RUN_URL RUN_STATUS <<< "$RUN_RECORD"
[[ "$RUN_ID" =~ ^[0-9]+$ ]] || fail "DISPATCHED_RUNTIME_PLAN_RUN_ID_INVALID"
[[ -n "$RUN_URL" ]] || fail "DISPATCHED_RUNTIME_PLAN_RUN_URL_MISSING"

printf '%s\n' \
  "RuntimeDependenciesPlanDispatch=success" \
  "RepositoryHead=${ACTUAL_HEAD:0:12}" \
  "NetworkApplyVerified=true" \
  "ExistingResourceCollision=false" \
  "ExistingResourceMode=${EXISTING_RESOURCE_MODE}" \
  "BaseRuntimeApplyVerified=${BASE_RUNTIME_APPLIED}" \
  "RuntimeTfvarsPrivate=true" \
  "RuntimeDependenciesSecretConfigured=true" \
  "LaterStageSecretsConfigured=false" \
  "InventoryStage=runtime-dependencies" \
  "PrerequisiteStrict=passed" \
  "PlanStage=runtime-dependencies" \
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
  "GitHubMutation=runtime-dependencies-secret"
