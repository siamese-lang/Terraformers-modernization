#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/inspect-partial-stateful-dependencies-apply.sh \
    --expected-head CURRENT_SHA \
    --apply-head APPLY_SHA

Inspect a failed or partial stateful-dependencies apply without changing AWS,
GitHub, Terraform state, or repository files. The command reports only resource
addresses, existence/status booleans, lock/state presence, and a sanitized error.
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
APPLY_HEAD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-head)
      [[ $# -ge 2 ]] || fail "EXPECTED_HEAD_VALUE_MISSING"
      EXPECTED_HEAD="$2"
      shift 2
      ;;
    --apply-head)
      [[ $# -ge 2 ]] || fail "APPLY_HEAD_VALUE_MISSING"
      APPLY_HEAD="$2"
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
[[ "$APPLY_HEAD" =~ ^[0-9a-f]{40}$ ]] || fail "APPLY_HEAD_INVALID"

for command_name in git aws cygpath sed grep head find; do
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
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
APPLY_SHORT="${APPLY_HEAD:0:12}"
WORK_DIR="$PRIVATE_DIR/stateful-dependencies-apply-${APPLY_SHORT}"
TF_EXE="$(cygpath -u "$LOCALAPPDATA")/Programs/Terraform/1.15.8/terraform.exe"
TF_DATA_DIR_UNIX="$WORK_DIR/tfdata"
TF_CLI_CONFIG="$WORK_DIR/terraform.tfrc"
BACKEND_CONFIG="$WORK_DIR/backend.hcl"
APPLY_LOG="$WORK_DIR/stateful-dependencies-apply.log"
STATEFUL_TFVARS="$PRIVATE_DIR/stateful-dependencies.live.tfvars"
STATE_LIST="$WORK_DIR/stateful-dependencies-partial-state-list.txt"
SANITIZED_ERROR="$WORK_DIR/stateful-dependencies-sanitized-error.txt"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "UNEXPECTED_CURRENT_BRANCH"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"

[[ -x "$TF_EXE" ]] || fail "TERRAFORM_1_15_8_NOT_FOUND"
[[ -d "$WORK_DIR" ]] || fail "STATEFUL_APPLY_WORK_DIRECTORY_NOT_FOUND"
[[ -d "$TF_DATA_DIR_UNIX" ]] || fail "STATEFUL_APPLY_TF_DATA_DIRECTORY_NOT_FOUND"
[[ -f "$TF_CLI_CONFIG" ]] || fail "STATEFUL_APPLY_TERRAFORM_CONFIG_NOT_FOUND"
[[ -f "$BACKEND_CONFIG" ]] || fail "STATEFUL_APPLY_BACKEND_CONFIG_NOT_FOUND"
[[ -f "$APPLY_LOG" ]] || fail "STATEFUL_APPLY_LOG_NOT_FOUND"
[[ -f "$STATEFUL_TFVARS" ]] || fail "PRIVATE_STATEFUL_TFVARS_NOT_FOUND"

aws sts get-caller-identity --output json >/dev/null 2>&1 || fail "AWS_IDENTITY_UNAVAILABLE"

WORK_DIR_WIN="$(cygpath -am "$WORK_DIR")"
TF_DATA_DIR_WIN="$(cygpath -am "$TF_DATA_DIR_UNIX")"
TF_CLI_CONFIG_WIN="$(cygpath -am "$TF_CLI_CONFIG")"
export TF_DATA_DIR="$TF_DATA_DIR_WIN"
export TF_CLI_CONFIG_FILE="$TF_CLI_CONFIG_WIN"
export TF_IN_AUTOMATION=1
export GOGC="${GOGC:-25}"
unset TF_PLUGIN_CACHE_DIR || true

set +e
"$TF_EXE" -chdir="$WORK_DIR_WIN" state list > "$STATE_LIST" 2>/dev/null
STATE_LIST_EXIT=$?
set -e
if [[ "$STATE_LIST_EXIT" -ne 0 ]]; then
  : > "$STATE_LIST"
fi

MANAGED_STATE_COUNT="$(grep -v '^data\.' "$STATE_LIST" | grep -c . || true)"

DB_ID="terraformers-modernization-dev-mariadb"
DB_SUBNET_GROUP_NAME="terraformers-modernization-dev-db"
DB_SECURITY_GROUP_NAME="terraformers-modernization-dev-db"
COGNITO_POOL_NAME="terraformers-modernization-dev-users"
VPC_ID="$(sed -nE 's/^[[:space:]]*vpc_id[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$STATEFUL_TFVARS" | head -n 1)"
[[ "$VPC_ID" == vpc-* ]] || fail "STATEFUL_VPC_ID_INVALID"

RDS_STATUS="$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text 2>/dev/null || true)"
[[ -n "$RDS_STATUS" && "$RDS_STATUS" != "None" ]] || RDS_STATUS="absent"

if aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" >/dev/null 2>&1; then
  DB_SUBNET_GROUP_PRESENT=true
else
  DB_SUBNET_GROUP_PRESENT=false
fi

SG_COUNT="$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${DB_SECURITY_GROUP_NAME}" \
  --query 'length(SecurityGroups)' \
  --output text 2>/dev/null || true)"
[[ "$SG_COUNT" =~ ^[0-9]+$ ]] || SG_COUNT=0
if (( SG_COUNT > 0 )); then
  DATABASE_SECURITY_GROUP_PRESENT=true
else
  DATABASE_SECURITY_GROUP_PRESENT=false
fi

COGNITO_POOL_ID="$(aws cognito-idp list-user-pools \
  --max-results 60 \
  --query "UserPools[?Name=='${COGNITO_POOL_NAME}'].Id | [0]" \
  --output text 2>/dev/null || true)"
if [[ -n "$COGNITO_POOL_ID" && "$COGNITO_POOL_ID" != "None" ]]; then
  COGNITO_USER_POOL_PRESENT=true
  COGNITO_CLIENT_COUNT="$(aws cognito-idp list-user-pool-clients \
    --user-pool-id "$COGNITO_POOL_ID" \
    --max-results 60 \
    --query 'length(UserPoolClients)' \
    --output text 2>/dev/null || true)"
  [[ "$COGNITO_CLIENT_COUNT" =~ ^[0-9]+$ ]] || COGNITO_CLIENT_COUNT=0
else
  COGNITO_USER_POOL_PRESENT=false
  COGNITO_CLIENT_COUNT=0
fi

STATE_BUCKET="$(sed -nE 's/^[[:space:]]*bucket[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$BACKEND_CONFIG" | head -n 1)"
STATE_KEY="$(sed -nE 's/^[[:space:]]*key[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$BACKEND_CONFIG" | head -n 1)"
[[ -n "$STATE_BUCKET" && -n "$STATE_KEY" ]] || fail "STATEFUL_BACKEND_VALUES_MISSING"
if aws s3api head-object --bucket "$STATE_BUCKET" --key "$STATE_KEY" >/dev/null 2>&1; then
  REMOTE_STATE_PRESENT=true
else
  REMOTE_STATE_PRESENT=false
fi
if aws s3api head-object --bucket "$STATE_BUCKET" --key "${STATE_KEY}.tflock" >/dev/null 2>&1; then
  STALE_LOCK_PRESENT=true
else
  STALE_LOCK_PRESENT=false
fi

"${PYTHON_CMD[@]}" - "$APPLY_LOG" "$SANITIZED_ERROR" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
lines = source.read_text(encoding="utf-8", errors="replace").splitlines()
patterns = re.compile(
    r"Error:|AccessDenied|Unauthorized|Forbidden|Invalid|AlreadyExists|"
    r"LimitExceeded|Insufficient|Unsupported|failed|Failed|timeout|Timeout|"
    r"RequestID|StatusCode",
    re.IGNORECASE,
)
hits = [index for index, line in enumerate(lines) if patterns.search(line)]
if hits:
    start = max(0, hits[0] - 8)
    end = min(len(lines), hits[-1] + 24)
else:
    start = max(0, len(lines) - 80)
    end = len(lines)
text = "\n".join(lines[start:end])
redactions = [
    (r"\b\d{12}\b", "[AWS_ACCOUNT_ID]"),
    (r"arn:aws[a-zA-Z-]*:[^\s\"']+", "[AWS_ARN]"),
    (r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b", "[AWS_ACCESS_KEY_ID]"),
    (r"\b(?:vpc|subnet|sg|db|userpool|client)-[A-Za-z0-9-]+\b", "[RESOURCE_ID]"),
    (r"https://[^\s\"']+", "[URL]"),
    (r"request id:?[ ]*[A-Za-z0-9-]+", "request id: [REDACTED]"),
]
for expression, replacement in redactions:
    text = re.sub(expression, replacement, text, flags=re.IGNORECASE)
target.write_text(text + "\n", encoding="utf-8")
PY

printf '%s\n' \
  "StatefulPartialApplyInspection=completed" \
  "RepositoryHead=${ACTUAL_HEAD:0:12}" \
  "ApplyHead=${APPLY_SHORT}" \
  "TerraformStateReadable=$([[ "$STATE_LIST_EXIT" -eq 0 ]] && echo true || echo false)" \
  "ManagedStateResourceCount=${MANAGED_STATE_COUNT}" \
  "RdsInstanceStatus=${RDS_STATUS}" \
  "DbSubnetGroupPresent=${DB_SUBNET_GROUP_PRESENT}" \
  "DatabaseSecurityGroupPresent=${DATABASE_SECURITY_GROUP_PRESENT}" \
  "CognitoUserPoolPresent=${COGNITO_USER_POOL_PRESENT}" \
  "CognitoUserPoolClientCount=${COGNITO_CLIENT_COUNT}" \
  "RemoteStateObjectPresent=${REMOTE_STATE_PRESENT}" \
  "StaleLockObjectPresent=${STALE_LOCK_PRESENT}" \
  "SensitiveValuesPrinted=false" \
  "TerraformApplyExecuted=false" \
  "TerraformDestroyExecuted=false" \
  "AwsMutation=none" \
  "GitHubMutation=none" \
  "PythonCommand=${PYTHON_LABEL}"

printf '\nManagedStateAddresses:\n'
if [[ -s "$STATE_LIST" ]]; then
  cat "$STATE_LIST"
else
  printf '%s\n' '(none)'
fi

printf '\nSanitizedApplyError:\n'
cat "$SANITIZED_ERROR"
