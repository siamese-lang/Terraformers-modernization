#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/review-latest-runtime-dependencies-plan.sh \
    --expected-head CURRENT_SHA \
    --plan-head PLAN_SHA

Locate the successful runtime-dependencies plan for PLAN_SHA, download only its
sanitized artifact into a private directory, verify the exact approved
13-resource create set, and print the risk summary. CURRENT_SHA protects the
local review code. No AWS or GitHub mutation is performed.
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
PLAN_HEAD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-head)
      [[ $# -ge 2 ]] || fail "EXPECTED_HEAD_VALUE_MISSING"
      EXPECTED_HEAD="$2"
      shift 2
      ;;
    --plan-head)
      [[ $# -ge 2 ]] || fail "PLAN_HEAD_VALUE_MISSING"
      PLAN_HEAD="$2"
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
[[ "$PLAN_HEAD" =~ ^[0-9a-f]{40}$ ]] || fail "PLAN_HEAD_INVALID"

for command_name in git gh cygpath rm mkdir find grep sed head cp; do
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
STAGE="runtime-dependencies"
ARTIFACT_NAME="aws-live-terraform-plan-${STAGE}-evidence"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
PLAN_SHORT="${PLAN_HEAD:0:12}"
SOURCE_DIR="$PRIVATE_DIR/${STAGE}-plan-source-${PLAN_SHORT}"
REVIEW_DIR="$PRIVATE_DIR/${STAGE}-plan-review-${PLAN_SHORT}"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "UNEXPECTED_CURRENT_BRANCH"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"
git cat-file -e "${PLAN_HEAD}^{commit}" 2>/dev/null || fail "PLAN_HEAD_COMMIT_NOT_FOUND"
if ! git diff --quiet "$PLAN_HEAD" "$ACTUAL_HEAD" -- infra/terraform/envs/backend-runtime-dependencies; then
  fail "RUNTIME_DEPENDENCIES_CONFIGURATION_CHANGED_SINCE_PLAN"
fi
gh auth status --hostname github.com >/dev/null 2>&1 || fail "GITHUB_AUTH_UNAVAILABLE"

RUN_RECORD="$(gh api \
  "repos/${REPO}/actions/workflows/${WORKFLOW}/runs?branch=${BRANCH}&event=workflow_dispatch&status=completed&per_page=50" \
  --jq ".workflow_runs[] | select(.head_sha == \"${PLAN_HEAD}\" and .conclusion == \"success\") | [.id, .html_url] | @tsv" \
  | head -n 1)"
[[ -n "$RUN_RECORD" ]] || fail "SUCCESSFUL_RUNTIME_DEPENDENCIES_PLAN_RUN_NOT_FOUND"
IFS=$'\t' read -r RUN_ID RUN_URL <<< "$RUN_RECORD"
[[ "$RUN_ID" =~ ^[0-9]+$ ]] || fail "RUNTIME_DEPENDENCIES_PLAN_RUN_ID_INVALID"
[[ -n "$RUN_URL" ]] || fail "RUNTIME_DEPENDENCIES_PLAN_RUN_URL_MISSING"

ARTIFACT_RECORD="$(gh api \
  "repos/${REPO}/actions/runs/${RUN_ID}/artifacts" \
  --jq ".artifacts[] | select(.name == \"${ARTIFACT_NAME}\" and .expired == false) | [.id, .name] | @tsv" \
  | head -n 1)"
[[ -n "$ARTIFACT_RECORD" ]] || fail "RUNTIME_DEPENDENCIES_PLAN_ARTIFACT_NOT_FOUND"
IFS=$'\t' read -r ARTIFACT_ID RESOLVED_ARTIFACT_NAME <<< "$ARTIFACT_RECORD"
[[ "$ARTIFACT_ID" =~ ^[0-9]+$ ]] || fail "RUNTIME_DEPENDENCIES_PLAN_ARTIFACT_ID_INVALID"
[[ "$RESOLVED_ARTIFACT_NAME" == "$ARTIFACT_NAME" ]] || fail "RUNTIME_DEPENDENCIES_PLAN_ARTIFACT_NAME_MISMATCH"

rm -rf "$SOURCE_DIR" "$REVIEW_DIR"
mkdir -p "$SOURCE_DIR" "$REVIEW_DIR"

gh run download "$RUN_ID" \
  --repo "$REPO" \
  --name "$ARTIFACT_NAME" \
  --dir "$SOURCE_DIR"

RISK_TXT="$(find "$SOURCE_DIR" -type f -name plan-risk-summary.txt -print -quit)"
RISK_JSON="$(find "$SOURCE_DIR" -type f -name plan-risk-summary.json -print -quit)"
RISK_MD="$(find "$SOURCE_DIR" -type f -name plan-risk-summary.md -print -quit)"
LIVE_SUMMARY="$(find "$SOURCE_DIR" -type f -name live-plan-summary.txt -print -quit)"
[[ -f "$RISK_TXT" ]] || fail "PLAN_RISK_TEXT_NOT_FOUND"
[[ -f "$RISK_JSON" ]] || fail "PLAN_RISK_JSON_NOT_FOUND"
[[ -f "$RISK_MD" ]] || fail "PLAN_RISK_MARKDOWN_NOT_FOUND"
[[ -f "$LIVE_SUMMARY" ]] || fail "LIVE_PLAN_SUMMARY_NOT_FOUND"

grep -Fqx 'terraform_plan_risk_gate=passed' "$RISK_TXT" || fail "RUNTIME_DEPENDENCIES_PLAN_RISK_GATE_NOT_PASSED"
grep -Fqx 'plan_stage=runtime-dependencies' "$RISK_TXT" || fail "RUNTIME_DEPENDENCIES_PLAN_STAGE_MISMATCH"
grep -Fqx 'resource_change_count=13' "$RISK_TXT" || fail "RUNTIME_DEPENDENCIES_RESOURCE_COUNT_MISMATCH"
grep -Fqx 'destructive_resource_count=0' "$RISK_TXT" || fail "RUNTIME_DEPENDENCIES_DESTRUCTIVE_CHANGE_PRESENT"
grep -Fqx 'replacement_resource_count=0' "$RISK_TXT" || fail "RUNTIME_DEPENDENCIES_REPLACEMENT_PRESENT"
grep -Fqx 'public_exposure_finding_count=0' "$RISK_TXT" || fail "RUNTIME_DEPENDENCIES_PUBLIC_EXPOSURE_PRESENT"
grep -Fqx 'optional_adapter_resource_count=0' "$RISK_TXT" || fail "RUNTIME_DEPENDENCIES_OPTIONAL_ADAPTER_PRESENT"
grep -Fqx 'high_cost_resource_count=0' "$RISK_TXT" || fail "RUNTIME_DEPENDENCIES_HIGH_COST_COUNT_MISMATCH"
grep -Fqx 'raw_plan_uploaded=false' "$RISK_TXT" || fail "RUNTIME_DEPENDENCIES_RAW_PLAN_BOUNDARY_MISSING"
grep -Fqx 'expected_account_id_verified=true' "$LIVE_SUMMARY" || fail "EXPECTED_ACCOUNT_VERIFICATION_EVIDENCE_MISSING"

if find "$SOURCE_DIR" -type f \( -name '*.tfplan' -o -name 'live-plan.json' -o -name 'live.auto.tfvars' -o -name 'backend.hcl' -o -name 'caller-identity.json' \) -print -quit | grep -q .; then
  fail "SENSITIVE_OR_RAW_PLAN_MATERIAL_FOUND_IN_ARTIFACT"
fi
if grep -R -E -q '(^|[^0-9])[0-9]{12}([^0-9]|$)' "$SOURCE_DIR"; then
  fail "AWS_ACCOUNT_ID_FOUND_IN_ARTIFACT"
fi

"${PYTHON_CMD[@]}" - "$RISK_MD" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
row_pattern = re.compile(r'^\| `([^`]+)` \| `([^`]+)` \| `([^`]+)` \|$', re.MULTILINE)
actual = {
    (address, resource_type, tuple(action for action in actions.split(",") if action))
    for address, resource_type, actions in row_pattern.findall(text)
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
if actual != expected:
    raise SystemExit("RUNTIME_DEPENDENCIES_RESOURCE_ACTION_SET_MISMATCH")
print("ExpectedResourceActionMatch=true")
print("ExpectedResourceCount=13")
PY

cp "$RISK_TXT" "$REVIEW_DIR/plan-risk-summary.txt"
cp "$RISK_JSON" "$REVIEW_DIR/plan-risk-summary.json"
cp "$RISK_MD" "$REVIEW_DIR/plan-risk-summary.md"
cp "$LIVE_SUMMARY" "$REVIEW_DIR/live-plan-summary.txt"
rm -rf "$SOURCE_DIR"

printf '%s\n' \
  "RuntimeDependenciesPlanReview=passed" \
  "RepositoryHead=${ACTUAL_HEAD:0:12}" \
  "PlanSourceHead=${PLAN_SHORT}" \
  "PlanRunId=${RUN_ID}" \
  "PlanStage=${STAGE}" \
  "ResourceChangeCount=13" \
  "HighCostResourceCount=0" \
  "DestructiveResourceCount=0" \
  "ReplacementResourceCount=0" \
  "PublicExposureFindingCount=0" \
  "OptionalAdapterResourceCount=0" \
  "ExpectedResourceActionMatch=true" \
  "RawPlanUploaded=false" \
  "IdentityMetadataPresent=false" \
  "ArtifactRetained=true" \
  "PrivateReviewDirectoryCreated=true" \
  "PythonCommand=${PYTHON_LABEL}" \
  "SensitiveValuesPrinted=false" \
  "TerraformApplyExecuted=false" \
  "TerraformDestroyExecuted=false" \
  "AwsMutation=none" \
  "GitHubMutation=none" \
  "RunUrl=${RUN_URL}"

printf '\nResourceActions:\n'
sed -n '/^| `.*` | `.*` | `.*` |$/p' "$REVIEW_DIR/plan-risk-summary.md"
