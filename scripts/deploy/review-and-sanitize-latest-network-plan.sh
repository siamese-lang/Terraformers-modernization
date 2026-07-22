#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/review-and-sanitize-latest-network-plan.sh \
    --expected-head CURRENT_SHA \
    --plan-head PLAN_SHA

The command locates the successful pre-merge network plan for PLAN_SHA,
downloads its artifact to a private directory, preserves only the sanitized
risk summary, and deletes the source artifact because the first run may contain
AWS identity metadata. It performs no AWS mutation and never prints account IDs.
EOF
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
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

REPO="siamese-lang/Terraformers-modernization"
WORKFLOW="runtime-contract-verification.yml"
BRANCH="agent/rdb-domain-realignment"
ARTIFACT_NAME="aws-live-terraform-plan-network-evidence"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
PLAN_SHORT="${PLAN_HEAD:0:12}"
SOURCE_DIR="$PRIVATE_DIR/network-plan-source-${PLAN_SHORT}"
REVIEW_DIR="$PRIVATE_DIR/network-plan-review-${PLAN_SHORT}"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "UNEXPECTED_CURRENT_BRANCH"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}

ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"
gh auth status --hostname github.com >/dev/null 2>&1 || fail "GITHUB_AUTH_UNAVAILABLE"

RUN_RECORD="$(gh api \
  "repos/${REPO}/actions/workflows/${WORKFLOW}/runs?branch=${BRANCH}&event=workflow_dispatch&status=completed&per_page=50" \
  --jq ".workflow_runs[] | select(.head_sha == \"${PLAN_HEAD}\" and .conclusion == \"success\") | [.id, .html_url] | @tsv" \
  | head -n 1)"
[[ -n "$RUN_RECORD" ]] || fail "SUCCESSFUL_NETWORK_PLAN_RUN_NOT_FOUND"
IFS=$'\t' read -r RUN_ID RUN_URL <<< "$RUN_RECORD"
[[ "$RUN_ID" =~ ^[0-9]+$ ]] || fail "NETWORK_PLAN_RUN_ID_INVALID"
[[ -n "$RUN_URL" ]] || fail "NETWORK_PLAN_RUN_URL_MISSING"

ARTIFACT_RECORD="$(gh api \
  "repos/${REPO}/actions/runs/${RUN_ID}/artifacts" \
  --jq ".artifacts[] | select(.name == \"${ARTIFACT_NAME}\" and .expired == false) | [.id, .name] | @tsv" \
  | head -n 1)"
[[ -n "$ARTIFACT_RECORD" ]] || fail "NETWORK_PLAN_ARTIFACT_NOT_FOUND"
IFS=$'\t' read -r ARTIFACT_ID RESOLVED_ARTIFACT_NAME <<< "$ARTIFACT_RECORD"
[[ "$ARTIFACT_ID" =~ ^[0-9]+$ ]] || fail "NETWORK_PLAN_ARTIFACT_ID_INVALID"
[[ "$RESOLVED_ARTIFACT_NAME" == "$ARTIFACT_NAME" ]] || fail "NETWORK_PLAN_ARTIFACT_NAME_MISMATCH"

rm -rf "$SOURCE_DIR" "$REVIEW_DIR"
mkdir -p "$SOURCE_DIR" "$REVIEW_DIR"

gh run download "$RUN_ID" \
  --repo "$REPO" \
  --name "$ARTIFACT_NAME" \
  --dir "$SOURCE_DIR"

RISK_TXT="$(find "$SOURCE_DIR" -type f -name plan-risk-summary.txt -print -quit)"
RISK_JSON="$(find "$SOURCE_DIR" -type f -name plan-risk-summary.json -print -quit)"
RISK_MD="$(find "$SOURCE_DIR" -type f -name plan-risk-summary.md -print -quit)"
[[ -f "$RISK_TXT" ]] || fail "PLAN_RISK_TEXT_NOT_FOUND"
[[ -f "$RISK_JSON" ]] || fail "PLAN_RISK_JSON_NOT_FOUND"
[[ -f "$RISK_MD" ]] || fail "PLAN_RISK_MARKDOWN_NOT_FOUND"

grep -Fqx 'terraform_plan_risk_gate=passed' "$RISK_TXT" || fail "NETWORK_PLAN_RISK_GATE_NOT_PASSED"
grep -Fqx 'plan_stage=network' "$RISK_TXT" || fail "NETWORK_PLAN_STAGE_MISMATCH"
grep -Fqx 'destructive_resource_count=0' "$RISK_TXT" || fail "NETWORK_PLAN_DESTRUCTIVE_CHANGE_PRESENT"
grep -Fqx 'replacement_resource_count=0' "$RISK_TXT" || fail "NETWORK_PLAN_REPLACEMENT_PRESENT"
grep -Fqx 'public_exposure_finding_count=0' "$RISK_TXT" || fail "NETWORK_PLAN_PUBLIC_EXPOSURE_PRESENT"
grep -Fqx 'optional_adapter_resource_count=0' "$RISK_TXT" || fail "NETWORK_PLAN_OPTIONAL_ADAPTER_PRESENT"
grep -Fqx 'raw_plan_uploaded=false' "$RISK_TXT" || fail "NETWORK_PLAN_RAW_PLAN_BOUNDARY_MISSING"

if find "$SOURCE_DIR" -type f \( -name '*.tfplan' -o -name 'live-plan.json' -o -name 'live.auto.tfvars' -o -name 'backend.hcl' \) -print -quit | grep -q .; then
  fail "RAW_PLAN_MATERIAL_FOUND_IN_ARTIFACT"
fi

IDENTITY_METADATA_PRESENT=false
if find "$SOURCE_DIR" -type f -name caller-identity.json -print -quit | grep -q .; then
  IDENTITY_METADATA_PRESENT=true
fi
if grep -R -E -q '^expected_account_id=[0-9]{12}$' "$SOURCE_DIR"; then
  IDENTITY_METADATA_PRESENT=true
fi

cp "$RISK_TXT" "$REVIEW_DIR/plan-risk-summary.txt"
cp "$RISK_JSON" "$REVIEW_DIR/plan-risk-summary.json"
cp "$RISK_MD" "$REVIEW_DIR/plan-risk-summary.md"

RESOURCE_CHANGE_COUNT="$(sed -n 's/^resource_change_count=//p' "$RISK_TXT")"
HIGH_COST_RESOURCE_COUNT="$(sed -n 's/^high_cost_resource_count=//p' "$RISK_TXT")"
[[ "$RESOURCE_CHANGE_COUNT" =~ ^[0-9]+$ ]] || fail "RESOURCE_CHANGE_COUNT_INVALID"
[[ "$HIGH_COST_RESOURCE_COUNT" =~ ^[0-9]+$ ]] || fail "HIGH_COST_RESOURCE_COUNT_INVALID"

{
  printf '%s\n' \
    "NetworkPlanReview=passed" \
    "PlanSourceHead=${PLAN_SHORT}" \
    "PlanRunId=${RUN_ID}" \
    "PlanStage=network" \
    "ResourceChangeCount=${RESOURCE_CHANGE_COUNT}" \
    "HighCostResourceCount=${HIGH_COST_RESOURCE_COUNT}" \
    "DestructiveResourceCount=0" \
    "ReplacementResourceCount=0" \
    "PublicExposureFindingCount=0" \
    "OptionalAdapterResourceCount=0" \
    "RawPlanUploaded=false" \
    "SourceArtifactContainedIdentityMetadata=${IDENTITY_METADATA_PRESENT}" \
    "SensitiveValuesPrinted=false" \
    "TerraformApplyExecuted=false" \
    "TerraformDestroyExecuted=false" \
    "AwsMutation=none"
} > "$REVIEW_DIR/review-summary.txt"

gh api --method DELETE "repos/${REPO}/actions/artifacts/${ARTIFACT_ID}" >/dev/null
rm -rf "$SOURCE_DIR"

cat "$REVIEW_DIR/review-summary.txt"
printf '%s\n' "SourceArtifactDeleted=true" "RunUrl=${RUN_URL}"
printf '\nResourceActions:\n'
sed -n '/^| `.*` | `.*` | `.*` |$/p' "$REVIEW_DIR/plan-risk-summary.md"
