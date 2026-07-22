#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/inventory-live-aws-prerequisites.sh \
    --expected-head SHA [--stage STAGE] [--strict]

Stages:
  network (default)
  runtime-dependencies
  stateful-dependencies
  eks-runtime
  frontend-delivery
  all

Default mode inventories the current GitHub and AWS prerequisite state without
failing on missing GitHub configuration. --strict requires the selected stage
prerequisites to be present. This command is read-only and never prints Secret
values.
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
    "$TFVARS_PATH" |
    head -n 1
}

EXPECTED_HEAD=""
STAGE="network"
STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-head)
      [[ $# -ge 2 ]] || fail "EXPECTED_HEAD_VALUE_MISSING"
      EXPECTED_HEAD="$2"
      shift 2
      ;;
    --stage)
      [[ $# -ge 2 ]] || fail "STAGE_VALUE_MISSING"
      STAGE="$2"
      shift 2
      ;;
    --strict)
      STRICT=true
      shift
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
case "$STAGE" in
  network|runtime-dependencies|stateful-dependencies|eks-runtime|frontend-delivery|all)
    ;;
  *)
    fail "UNKNOWN_STAGE: $STAGE"
    ;;
esac

for command_name in git gh aws cygpath sed; do
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
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
TFVARS_PATH="$PRIVATE_DIR/foundation.tfvars"
CONTRACT_PATH="$REPO_ROOT/config/live-aws-prerequisites.json"
SCOPED_CONTRACT_PATH="$PRIVATE_DIR/live-aws-prerequisites.${STAGE}.json"
SUMMARY_PATH="$REPO_ROOT/artifacts/live-aws-prerequisite-inventory/prerequisite-summary.txt"

[[ -f "$TFVARS_PATH" ]] || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
[[ -f "$CONTRACT_PATH" ]] || fail "LIVE_AWS_PREREQUISITE_CONTRACT_NOT_FOUND"

cd "$REPO_ROOT"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}

ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"

gh auth status --hostname github.com >/dev/null 2>&1 || fail "GITHUB_AUTH_UNAVAILABLE"
aws sts get-caller-identity --output json >/dev/null 2>&1 || fail "AWS_IDENTITY_UNAVAILABLE"

EXPECTED_ACCOUNT_ID="$(read_tfvar_string expected_aws_account_id)"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "EXPECTED_ACCOUNT_ID_INVALID"

"${PYTHON_CMD[@]}" - "$CONTRACT_PATH" "$SCOPED_CONTRACT_PATH" "$STAGE" <<'PY'
import json
import sys
from pathlib import Path

contract_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
stage = sys.argv[3]
contract = json.loads(contract_path.read_text(encoding="utf-8"))

all_secrets = contract.get("required_github_secrets", [])
stage_mapping = contract.get("required_github_secrets_by_stage", {})
stage_ids = [item.get("id") for item in contract.get("terraform_stages", [])]

if set(stage_mapping) != set(stage_ids):
    raise SystemExit("STAGE_SECRET_MAPPING_DRIFT")

mapped_secrets = [secret for secrets in stage_mapping.values() for secret in secrets]
if sorted(mapped_secrets) != sorted(all_secrets):
    raise SystemExit("STAGE_SECRET_SET_DRIFT")

if stage != "all":
    selected = stage_mapping.get(stage)
    if selected is None:
        raise SystemExit(f"UNKNOWN_STAGE: {stage}")
    contract["required_github_secrets"] = selected

contract["inventory_stage"] = stage
output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(contract, indent=2) + "\n", encoding="utf-8")
PY

ARGS=(
  scripts/deploy/live-aws-prerequisite-inventory.py
  --contract "$SCOPED_CONTRACT_PATH"
  --expected-account-id "$EXPECTED_ACCOUNT_ID"
)
if [[ "$STRICT" == true ]]; then
  ARGS+=(--fail-on-missing)
fi

set +e
"${PYTHON_CMD[@]}" "${ARGS[@]}"
INVENTORY_EXIT_CODE=$?
set -e

[[ -f "$SUMMARY_PATH" ]] || fail "PREREQUISITE_SUMMARY_NOT_CREATED"

printf '%s\n' \
  "PrerequisiteInventoryExecuted=true" \
  "RepositoryHead=${ACTUAL_HEAD:0:12}" \
  "InventoryStage=${STAGE}" \
  "PythonCommand=${PYTHON_LABEL}" \
  "StrictMode=${STRICT}" \
  "SecretValuesRead=false" \
  "AwsMutation=none"

exit "$INVENTORY_EXIT_CODE"
