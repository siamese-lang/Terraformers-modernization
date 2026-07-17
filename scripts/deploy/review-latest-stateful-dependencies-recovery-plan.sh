#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

python_is_usable() {
  local output
  output="$("$@" -c 'import sys; print(sys.version_info.major)' 2>/dev/null)" || return 1
  [[ "$output" == "3" ]]
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
STAGE="stateful-dependencies"
ARTIFACT_NAME="aws-live-terraform-plan-${STAGE}-evidence"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
PLAN_SHORT="${PLAN_HEAD:0:12}"
CANDIDATE_ROOT="$PRIVATE_DIR/stateful-dependencies-recovery-plan-candidates-${PLAN_SHORT}"
REVIEW_DIR="$PRIVATE_DIR/stateful-dependencies-recovery-plan-review-${PLAN_SHORT}"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "UNEXPECTED_CURRENT_BRANCH"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"
git cat-file -e "${PLAN_HEAD}^{commit}" 2>/dev/null || fail "PLAN_HEAD_COMMIT_NOT_FOUND"
if ! git diff --quiet "$PLAN_HEAD" "$ACTUAL_HEAD" -- infra/terraform/envs/backend-stateful-dependencies; then
  fail "STATEFUL_DEPENDENCIES_CONFIGURATION_CHANGED_SINCE_RECOVERY_PLAN"
fi

gh auth status --hostname github.com >/dev/null 2>&1 || fail "GITHUB_AUTH_UNAVAILABLE"

rm -rf "$CANDIDATE_ROOT" "$REVIEW_DIR"
mkdir -p "$CANDIDATE_ROOT" "$REVIEW_DIR"

RUN_RECORDS="$(gh api \
  "repos/${REPO}/actions/workflows/${WORKFLOW}/runs?branch=${BRANCH}&event=workflow_dispatch&status=completed&per_page=50" \
  --jq ".workflow_runs[] | select(.head_sha == \"${PLAN_HEAD}\" and .conclusion == \"success\") | [.id, .html_url] | @tsv")"
[[ -n "$RUN_RECORDS" ]] || fail "SUCCESSFUL_STATEFUL_RECOVERY_PLAN_RUN_NOT_FOUND"

SELECTED_RUN_ID=""
SELECTED_RUN_URL=""
SELECTED_SOURCE_DIR=""
while IFS=$'\t' read -r CANDIDATE_RUN_ID CANDIDATE_RUN_URL; do
  [[ "$CANDIDATE_RUN_ID" =~ ^[0-9]+$ ]] || continue
  CANDIDATE_DIR="$CANDIDATE_ROOT/$CANDIDATE_RUN_ID"
  mkdir -p "$CANDIDATE_DIR"

  ARTIFACT_RECORD="$(gh api \
    "repos/${REPO}/actions/runs/${CANDIDATE_RUN_ID}/artifacts" \
    --jq ".artifacts[] | select(.name == \"${ARTIFACT_NAME}\" and .expired == false) | [.id, .name] | @tsv" \
    | head -n 1)"
  [[ -n "$ARTIFACT_RECORD" ]] || continue

  if ! gh run download "$CANDIDATE_RUN_ID" \
    --repo "$REPO" \
    --name "$ARTIFACT_NAME" \
    --dir "$CANDIDATE_DIR" >/dev/null 2>&1; then
    continue
  fi

  CANDIDATE_RISK_TXT="$(find "$CANDIDATE_DIR" -type f -name plan-risk-summary.txt -print -quit)"
  CANDIDATE_RISK_MD="$(find "$CANDIDATE_DIR" -type f -name plan-risk-summary.md -print -quit)"
  CANDIDATE_LIVE_SUMMARY="$(find "$CANDIDATE_DIR" -type f -name live-plan-summary.txt -print -quit)"
  [[ -f "$CANDIDATE_RISK_TXT" && -f "$CANDIDATE_RISK_MD" && -f "$CANDIDATE_LIVE_SUMMARY" ]] || continue

  grep -Fqx 'terraform_plan_risk_gate=passed' "$CANDIDATE_RISK_TXT" || continue
  grep -Fqx 'plan_stage=stateful-dependencies' "$CANDIDATE_RISK_TXT" || continue
  grep -Fqx 'resource_change_count=1' "$CANDIDATE_RISK_TXT" || continue
  grep -Fq '| `aws_db_instance.backend` | `aws_db_instance` | `create` |' "$CANDIDATE_RISK_MD" || continue

  SELECTED_RUN_ID="$CANDIDATE_RUN_ID"
  SELECTED_RUN_URL="$CANDIDATE_RUN_URL"
  SELECTED_SOURCE_DIR="$CANDIDATE_DIR"
  break
done <<< "$RUN_RECORDS"

[[ -n "$SELECTED_RUN_ID" && -d "$SELECTED_SOURCE_DIR" ]] || fail "MATCHING_STATEFUL_RECOVERY_PLAN_ARTIFACT_NOT_FOUND"

RISK_TXT="$(find "$SELECTED_SOURCE_DIR" -type f -name plan-risk-summary.txt -print -quit)"
RISK_JSON="$(find "$SELECTED_SOURCE_DIR" -type f -name plan-risk-summary.json -print -quit)"
RISK_MD="$(find "$SELECTED_SOURCE_DIR" -type f -name plan-risk-summary.md -print -quit)"
LIVE_SUMMARY="$(find "$SELECTED_SOURCE_DIR" -type f -name live-plan-summary.txt -print -quit)"
[[ -f "$RISK_TXT" && -f "$RISK_JSON" && -f "$RISK_MD" && -f "$LIVE_SUMMARY" ]] || fail "STATEFUL_RECOVERY_PLAN_SUMMARY_MISSING"

grep -Fqx 'destructive_resource_count=0' "$RISK_TXT" || fail "STATEFUL_RECOVERY_DESTRUCTIVE_CHANGE_PRESENT"
grep -Fqx 'replacement_resource_count=0' "$RISK_TXT" || fail "STATEFUL_RECOVERY_REPLACEMENT_PRESENT"
grep -Fqx 'public_exposure_finding_count=0' "$RISK_TXT" || fail "STATEFUL_RECOVERY_PUBLIC_EXPOSURE_PRESENT"
grep -Fqx 'optional_adapter_resource_count=0' "$RISK_TXT" || fail "STATEFUL_RECOVERY_OPTIONAL_ADAPTER_PRESENT"
grep -Fqx 'high_cost_resource_count=1' "$RISK_TXT" || fail "STATEFUL_RECOVERY_HIGH_COST_COUNT_MISMATCH"
grep -Fqx 'raw_plan_uploaded=false' "$RISK_TXT" || fail "STATEFUL_RECOVERY_RAW_PLAN_BOUNDARY_MISSING"
grep -Fqx 'expected_account_id_verified=true' "$LIVE_SUMMARY" || fail "EXPECTED_ACCOUNT_VERIFICATION_EVIDENCE_MISSING"

if find "$SELECTED_SOURCE_DIR" -type f \( -name '*.tfplan' -o -name 'live-plan.json' -o -name 'live.auto.tfvars' -o -name 'backend.hcl' -o -name 'caller-identity.json' \) -print -quit | grep -q .; then
  fail "SENSITIVE_OR_RAW_PLAN_MATERIAL_FOUND_IN_ARTIFACT"
fi
if grep -R -E -q '(^|[^0-9])[0-9]{12}([^0-9]|$)' "$SELECTED_SOURCE_DIR"; then
  fail "AWS_ACCOUNT_ID_FOUND_IN_ARTIFACT"
fi

"${PYTHON_CMD[@]}" - "$RISK_MD" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
rows = re.findall(r'^\| `([^`]+)` \| `([^`]+)` \| `([^`]+)` \|$', text, re.MULTILINE)
actual = {(address, resource_type, tuple(actions.split(","))) for address, resource_type, actions in rows}
expected = {("aws_db_instance.backend", "aws_db_instance", ("create",))}
if actual != expected:
    raise SystemExit("STATEFUL_RECOVERY_RESOURCE_ACTION_SET_MISMATCH")
print("ExpectedRecoveryResourceActionMatch=true")
print("ExpectedRecoveryResourceCount=1")
PY

cp "$RISK_TXT" "$REVIEW_DIR/plan-risk-summary.txt"
cp "$RISK_JSON" "$REVIEW_DIR/plan-risk-summary.json"
cp "$RISK_MD" "$REVIEW_DIR/plan-risk-summary.md"
cp "$LIVE_SUMMARY" "$REVIEW_DIR/live-plan-summary.txt"
rm -rf "$CANDIDATE_ROOT"

printf '%s\n' \
  "StatefulDependenciesRecoveryPlanReview=passed" \
  "RepositoryHead=${ACTUAL_HEAD:0:12}" \
  "PlanSourceHead=${PLAN_SHORT}" \
  "PlanRunId=${SELECTED_RUN_ID}" \
  "PlanStage=${STAGE}" \
  "ResourceChangeCount=1" \
  "HighCostResourceCount=1" \
  "DestructiveResourceCount=0" \
  "ReplacementResourceCount=0" \
  "PublicExposureFindingCount=0" \
  "OptionalAdapterResourceCount=0" \
  "ExpectedRecoveryResourceActionMatch=true" \
  "RawPlanUploaded=false" \
  "SensitiveValuesPrinted=false" \
  "TerraformApplyExecuted=false" \
  "TerraformDestroyExecuted=false" \
  "AwsMutation=none" \
  "GitHubMutation=none" \
  "PythonCommand=${PYTHON_LABEL}" \
  "RunUrl=${SELECTED_RUN_URL}"

printf '\nResourceActions:\n'
sed -n '/^| `.*` | `.*` | `.*` |$/p' "$REVIEW_DIR/plan-risk-summary.md"
