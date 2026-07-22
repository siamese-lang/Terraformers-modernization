#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/dispatch-premerge-network-plan.sh \
    --expected-head SHA

This command verifies the network prerequisites and dispatches the registered
Runtime Contract Verification workflow on the current pre-merge branch with the
guarded reusable network plan enabled. It performs no Terraform apply/destroy.
EOF
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

read_tfvar_string() {
  local name="$1"
  sed -nE \
    "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" \
    "$TFVARS_PATH" |
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

[[ -n "$EXPECTED_HEAD" ]] || fail "EXPECTED_HEAD_REQUIRED"

for command_name in git gh cygpath sed head sleep; do
  command -v "$command_name" >/dev/null 2>&1 || fail "REQUIRED_COMMAND_NOT_FOUND: $command_name"
done

REPO="siamese-lang/Terraformers-modernization"
WORKFLOW="runtime-contract-verification.yml"
BRANCH="agent/rdb-domain-realignment"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
TFVARS_PATH="$PRIVATE_DIR/foundation.tfvars"

[[ -f "$TFVARS_PATH" ]] || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "UNEXPECTED_CURRENT_BRANCH"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}

ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"

gh auth status --hostname github.com >/dev/null 2>&1 || fail "GITHUB_AUTH_UNAVAILABLE"

EXPECTED_ACCOUNT_ID="$(read_tfvar_string expected_aws_account_id)"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "EXPECTED_ACCOUNT_ID_INVALID"

bash scripts/deploy/inventory-live-aws-prerequisites.sh \
  --expected-head "$EXPECTED_HEAD" \
  --stage network \
  --strict

gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref "$BRANCH" \
  -f execute_live_plan=true \
  -f plan_stage=network \
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

[[ -n "$RUN_RECORD" ]] || fail "DISPATCHED_RUN_NOT_FOUND"

IFS=$'\t' read -r RUN_ID RUN_URL RUN_STATUS <<< "$RUN_RECORD"
[[ "$RUN_ID" =~ ^[0-9]+$ ]] || fail "DISPATCHED_RUN_ID_INVALID"
[[ -n "$RUN_URL" ]] || fail "DISPATCHED_RUN_URL_MISSING"

printf '%s\n' \
  "PremergeNetworkPlanDispatch=success" \
  "RepositoryHead=${ACTUAL_HEAD:0:12}" \
  "Workflow=${WORKFLOW}" \
  "PlanStage=network" \
  "ExecuteLivePlan=true" \
  "AllowDestructive=false" \
  "AllowOptionalAdapters=false" \
  "Environment=aws-live-plan" \
  "EnvironmentApprovalRequired=true" \
  "RunId=${RUN_ID}" \
  "RunStatus=${RUN_STATUS}" \
  "RunUrl=${RUN_URL}" \
  "ExpectedAccountIdPrinted=false" \
  "TerraformApplyExecuted=false" \
  "TerraformDestroyExecuted=false" \
  "AwsMutation=read-only-plan"
