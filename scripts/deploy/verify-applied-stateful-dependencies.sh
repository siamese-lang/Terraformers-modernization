#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/verify-applied-stateful-dependencies.sh \
    --expected-head CURRENT_SHA

Verify an already-applied stateful-dependencies stage without changing AWS
resources or Terraform state. Raw command evidence is written only below the
private live-foundation directory; standard output contains sanitized status.

Prerequisite: database_instance_identifier must already be synchronized into
remote state through a separately approved saved refresh-only plan. This
verifier does not synchronize outputs and must not use the recovery apply path.
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

strip_trailing_carriage_return() {
  local value="$1"
  printf '%s' "${value%$'\r'}"
}

read_tfvar_string() {
  local name="$1"
  sed -nE \
    "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" \
    "$FOUNDATION_TFVARS" |
    head -n 1
}

lock_object_status() {
  local error_log="$1"
  local exit_code
  set +e
  aws s3api head-object --bucket "$STATE_BUCKET" --key "${STATE_KEY}.tflock" \
    >/dev/null 2>"$error_log"
  exit_code=$?
  set -e
  if [[ "$exit_code" -eq 0 ]]; then
    printf '%s\n' "present"
  elif grep -Eq '(^|[^0-9])404([^0-9]|$)|Not Found|NoSuchKey' "$error_log"; then
    printf '%s\n' "absent"
  else
    printf '%s\n' "lookup-failed"
  fi
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
      fail "UNKNOWN_ARGUMENT"
      ;;
  esac
done

[[ "$EXPECTED_HEAD" =~ ^[0-9a-f]{40}$ ]] || fail "EXPECTED_HEAD_INVALID"

for command_name in git aws cygpath sed grep head mkdir cp date; do
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
STATEFUL_SOURCE="$REPO_ROOT/infra/terraform/envs/backend-stateful-dependencies"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
FOUNDATION_TFVARS="$PRIVATE_DIR/foundation.tfvars"
FOUNDATION_STATE="$PRIVATE_DIR/foundation.remote-post-migration.tfstate"
STATEFUL_TFVARS="$PRIVATE_DIR/stateful-dependencies.live.tfvars"
TF_EXE="$(cygpath -u "$LOCALAPPDATA")/Programs/Terraform/1.15.8/terraform.exe"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-${EXPECTED_HEAD:0:12}"
WORK_DIR="$PRIVATE_DIR/stateful-dependencies-verification-${RUN_ID}"
TF_DATA_DIR_UNIX="$WORK_DIR/tfdata"
TF_CLI_CONFIG="$WORK_DIR/terraform.tfrc"
BACKEND_CONFIG="$WORK_DIR/backend.hcl"
INIT_LOG="$WORK_DIR/terraform-init.log"
TERRAFORM_ERROR_LOG="$WORK_DIR/terraform-errors.log"
AWS_ERROR_LOG="$WORK_DIR/aws-errors.log"
STATE_LIST="$WORK_DIR/stateful-dependencies-state-list.txt"
OUTPUTS_JSON="$WORK_DIR/stateful-dependencies-outputs.json"
RDS_JSON="$WORK_DIR/rds-verification.json"
SG_JSON="$WORK_DIR/database-security-group-verification.json"
COGNITO_POOL_JSON="$WORK_DIR/cognito-user-pool-verification.json"
COGNITO_CLIENT_JSON="$WORK_DIR/cognito-user-pool-client-verification.json"
LOCK_ERROR_LOG="$WORK_DIR/stale-lock-head-error.log"
POST_PLAN_LOCK_ERROR_LOG="$WORK_DIR/post-plan-lock-head-error.log"
PLAN_PATH="$WORK_DIR/stateful-dependencies-verification.tfplan"
PLAN_LOG="$WORK_DIR/stateful-dependencies-verification-plan.log"
PLAN_JSON="$WORK_DIR/stateful-dependencies-verification-plan.json"
SUMMARY_PATH="$WORK_DIR/stateful-dependencies-verification-summary.txt"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "UNEXPECTED_CURRENT_BRANCH"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH"

[[ -x "$TF_EXE" ]] || fail "TERRAFORM_1_15_8_NOT_FOUND"
[[ -f "$FOUNDATION_TFVARS" ]] || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
[[ -f "$FOUNDATION_STATE" ]] || fail "VERIFIED_FOUNDATION_STATE_NOT_FOUND"
[[ -f "$STATEFUL_TFVARS" ]] || fail "PRIVATE_STATEFUL_DEPENDENCIES_TFVARS_NOT_FOUND"
[[ ! -e "$WORK_DIR" ]] || fail "STATEFUL_VERIFICATION_WORK_DIRECTORY_ALREADY_EXISTS"

mkdir -p "$WORK_DIR" "$TF_DATA_DIR_UNIX"
: >"$TERRAFORM_ERROR_LOG"
: >"$AWS_ERROR_LOG"
cp "$STATEFUL_SOURCE"/*.tf "$WORK_DIR/"

cat >"$WORK_DIR/backend.tf" <<'EOF'
terraform {
  backend "s3" {}
}
EOF
cat >"$TF_CLI_CONFIG" <<'EOF'
disable_checkpoint = true
EOF

EXPECTED_ACCOUNT_ID="$(read_tfvar_string expected_aws_account_id)"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "EXPECTED_ACCOUNT_ID_INVALID"

"${PYTHON_CMD[@]}" - "$FOUNDATION_STATE" "$BACKEND_CONFIG" "$EXPECTED_ACCOUNT_ID" <<'PY'
import json
import sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
backend_path = Path(sys.argv[2])
expected_account = sys.argv[3]
outputs = state.get("outputs", {})

def value(name: str) -> str:
    entry = outputs.get(name)
    resolved = entry.get("value") if isinstance(entry, dict) else None
    if not isinstance(resolved, str) or not resolved.strip():
        raise SystemExit(f"FOUNDATION_OUTPUT_INVALID: {name}")
    return resolved.strip()

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
    f'key          = "{prefix}/stateful-dependencies/terraform.tfstate"\n'
    f'region       = "{region}"\n'
    'encrypt      = true\n'
    'use_lockfile = true\n',
    encoding="utf-8",
)
PY

CALLER_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>>"$AWS_ERROR_LOG")" ||
  fail "AWS_IDENTITY_UNAVAILABLE"
[[ "$CALLER_ACCOUNT_ID" == "$EXPECTED_ACCOUNT_ID" ]] || fail "AWS_ACCOUNT_MISMATCH"

TERRAFORM_VERSION="$($TF_EXE version | sed -n '1p')"
[[ "$TERRAFORM_VERSION" == "Terraform v1.15.8" ]] || fail "TERRAFORM_VERSION_MISMATCH"

BACKEND_CONFIG_WIN="$(cygpath -am "$BACKEND_CONFIG")"
STATEFUL_TFVARS_WIN="$(cygpath -am "$STATEFUL_TFVARS")"
PLAN_PATH_WIN="$(cygpath -am "$PLAN_PATH")"
TF_DATA_DIR_WIN="$(cygpath -am "$TF_DATA_DIR_UNIX")"
TF_CLI_CONFIG_WIN="$(cygpath -am "$TF_CLI_CONFIG")"
WORK_DIR_WIN="$(cygpath -am "$WORK_DIR")"

export TF_DATA_DIR="$TF_DATA_DIR_WIN"
export TF_CLI_CONFIG_FILE="$TF_CLI_CONFIG_WIN"
export TF_IN_AUTOMATION=1
export GOGC="${GOGC:-25}"
export AWS_RETRY_MODE="${AWS_RETRY_MODE:-standard}"
export AWS_MAX_ATTEMPTS="${AWS_MAX_ATTEMPTS:-10}"
unset TF_PLUGIN_CACHE_DIR || true

"$TF_EXE" -chdir="$WORK_DIR_WIN" init \
  -input=false \
  -reconfigure \
  -backend-config="$BACKEND_CONFIG_WIN" >"$INIT_LOG" 2>&1 ||
  fail "STATEFUL_VERIFICATION_TERRAFORM_INIT_FAILED"

STATE_BUCKET="$(sed -nE 's/^[[:space:]]*bucket[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$BACKEND_CONFIG" | head -n 1)"
STATE_KEY="$(sed -nE 's/^[[:space:]]*key[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$BACKEND_CONFIG" | head -n 1)"
[[ -n "$STATE_BUCKET" && -n "$STATE_KEY" ]] || fail "STATEFUL_VERIFICATION_BACKEND_VALUES_MISSING"

aws s3api head-object --bucket "$STATE_BUCKET" --key "$STATE_KEY" \
  >/dev/null 2>>"$AWS_ERROR_LOG" || fail "STATEFUL_VERIFICATION_REMOTE_STATE_OBJECT_MISSING"

PRE_PLAN_LOCK_STATUS="$(lock_object_status "$LOCK_ERROR_LOG")"
[[ "$PRE_PLAN_LOCK_STATUS" != "lookup-failed" ]] || fail "STATEFUL_VERIFICATION_LOCK_LOOKUP_FAILED_BEFORE_PLAN"

"$TF_EXE" -chdir="$WORK_DIR_WIN" state list >"$STATE_LIST" 2>>"$TERRAFORM_ERROR_LOG" ||
  fail "STATEFUL_VERIFICATION_STATE_LIST_FAILED"
MANAGED_STATE_COUNT="$(grep -v '^data\.' "$STATE_LIST" | grep -c . || true)"
[[ "$MANAGED_STATE_COUNT" == "5" ]] || fail "STATEFUL_VERIFICATION_MANAGED_STATE_COUNT_MISMATCH"
for address in \
  aws_cognito_user_pool.backend \
  aws_cognito_user_pool_client.backend \
  aws_db_instance.backend \
  aws_db_subnet_group.backend \
  aws_security_group.backend_database; do
  grep -Fqx "$address" "$STATE_LIST" || fail "STATEFUL_VERIFICATION_STATE_ADDRESS_MISSING"
done

"$TF_EXE" -chdir="$WORK_DIR_WIN" output -json >"$OUTPUTS_JSON" 2>>"$TERRAFORM_ERROR_LOG" ||
  fail "STATEFUL_VERIFICATION_OUTPUT_READ_FAILED"
OUTPUT_RECORD="$("${PYTHON_CMD[@]}" - "$OUTPUTS_JSON" <<'PY'
import json
import sys
from pathlib import Path

outputs = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
required_strings = (
    "database_security_group_id",
    "database_instance_id",
    "database_master_user_secret_arn",
    "cognito_user_pool_id",
    "cognito_user_pool_client_id",
)
for name in required_strings:
    value = outputs.get(name, {}).get("value")
    if not isinstance(value, str) or not value:
        raise SystemExit(f"STATEFUL_VERIFICATION_OUTPUT_INVALID: {name}")
identifier = outputs.get("database_instance_identifier", {}).get("value")
if not isinstance(identifier, str) or not identifier:
    raise SystemExit("STATEFUL_VERIFICATION_DATABASE_IDENTIFIER_OUTPUT_NOT_SYNCHRONIZED")
if identifier != "terraformers-modernization-dev-mariadb":
    raise SystemExit("STATEFUL_VERIFICATION_DATABASE_IDENTIFIER_MISMATCH")
for name in (
    "database_instance_identifier",
    "database_security_group_id",
    "cognito_user_pool_id",
    "cognito_user_pool_client_id",
    "database_master_user_secret_arn",
):
    print(f'{name}\t{outputs[name]["value"]}')
PY
)"
DB_INSTANCE_IDENTIFIER=""
SG_ID=""
POOL_ID=""
CLIENT_ID=""
MASTER_SECRET_ARN=""
while IFS=$'\t' read -r name value; do
  value="$(strip_trailing_carriage_return "$value")"
  case "$name" in
    database_instance_identifier) DB_INSTANCE_IDENTIFIER="$value" ;;
    database_security_group_id) SG_ID="$value" ;;
    cognito_user_pool_id) POOL_ID="$value" ;;
    cognito_user_pool_client_id) CLIENT_ID="$value" ;;
    database_master_user_secret_arn) MASTER_SECRET_ARN="$value" ;;
    *) fail "STATEFUL_VERIFICATION_OUTPUT_RECORD_INVALID" ;;
  esac
done <<<"$OUTPUT_RECORD"
[[ -n "$DB_INSTANCE_IDENTIFIER" && -n "$SG_ID" && -n "$POOL_ID" && -n "$CLIENT_ID" && -n "$MASTER_SECRET_ARN" ]] ||
  fail "STATEFUL_VERIFICATION_IDENTIFIERS_MISSING"

aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" --output json \
  >"$RDS_JSON" 2>>"$AWS_ERROR_LOG" || fail "STATEFUL_VERIFICATION_RDS_LOOKUP_FAILED"
aws ec2 describe-security-groups --group-ids "$SG_ID" --output json \
  >"$SG_JSON" 2>>"$AWS_ERROR_LOG" || fail "STATEFUL_VERIFICATION_SECURITY_GROUP_LOOKUP_FAILED"
aws cognito-idp describe-user-pool --user-pool-id "$POOL_ID" --output json \
  >"$COGNITO_POOL_JSON" 2>>"$AWS_ERROR_LOG" || fail "STATEFUL_VERIFICATION_COGNITO_POOL_LOOKUP_FAILED"
aws cognito-idp describe-user-pool-client --user-pool-id "$POOL_ID" --client-id "$CLIENT_ID" --output json \
  >"$COGNITO_CLIENT_JSON" 2>>"$AWS_ERROR_LOG" || fail "STATEFUL_VERIFICATION_COGNITO_CLIENT_LOOKUP_FAILED"
aws secretsmanager describe-secret --secret-id "$MASTER_SECRET_ARN" \
  >/dev/null 2>>"$AWS_ERROR_LOG" || fail "STATEFUL_VERIFICATION_SECRET_CONTAINER_MISSING"

"${PYTHON_CMD[@]}" - "$RDS_JSON" "$SG_JSON" "$COGNITO_POOL_JSON" "$COGNITO_CLIENT_JSON" "$STATEFUL_TFVARS" <<'PY'
import json
import re
import sys
from pathlib import Path

rds = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["DBInstances"][0]
sg = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))["SecurityGroups"][0]
pool = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))["UserPool"]
client = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))["UserPoolClient"]
tfvars = Path(sys.argv[5]).read_text(encoding="utf-8")

expected_rds = {
    "DBInstanceStatus": "available",
    "Engine": "mariadb",
    "DBInstanceClass": "db.t4g.micro",
    "AllocatedStorage": 20,
    "BackupRetentionPeriod": 1,
    "StorageEncrypted": True,
    "PubliclyAccessible": False,
    "MultiAZ": False,
}
for key, expected in expected_rds.items():
    if rds.get(key) != expected:
        raise SystemExit(f"STATEFUL_VERIFICATION_RDS_PROPERTY_MISMATCH: {key}")
if not isinstance(rds.get("MasterUserSecret", {}).get("SecretArn"), str):
    raise SystemExit("STATEFUL_VERIFICATION_MANAGED_SECRET_METADATA_MISSING")

match = re.search(r'allowed_database_cidr_blocks\s*=\s*\[(.*?)\]', tfvars, re.DOTALL)
if not match:
    raise SystemExit("STATEFUL_VERIFICATION_ALLOWED_DATABASE_CIDRS_NOT_FOUND")
expected_cidrs = set(re.findall(r'"([0-9.]+/[0-9]+)"', match.group(1)))
if len(expected_cidrs) != 2 or "0.0.0.0/0" in expected_cidrs:
    raise SystemExit("STATEFUL_VERIFICATION_ALLOWED_DATABASE_CIDRS_INVALID")
actual_cidrs = set()
for permission in sg.get("IpPermissions", []):
    if permission.get("IpProtocol") != "tcp" or permission.get("FromPort") != 3306 or permission.get("ToPort") != 3306:
        raise SystemExit("STATEFUL_VERIFICATION_DATABASE_INGRESS_UNEXPECTED")
    if permission.get("Ipv6Ranges") or permission.get("UserIdGroupPairs") or permission.get("PrefixListIds"):
        raise SystemExit("STATEFUL_VERIFICATION_DATABASE_NON_CIDR_INGRESS_PRESENT")
    actual_cidrs.update(item.get("CidrIp") for item in permission.get("IpRanges", []))
if actual_cidrs != expected_cidrs:
    raise SystemExit("STATEFUL_VERIFICATION_DATABASE_CIDR_MISMATCH")

if pool.get("Name") != "terraformers-modernization-dev-users":
    raise SystemExit("STATEFUL_VERIFICATION_COGNITO_POOL_NAME_MISMATCH")
if pool.get("DeletionProtection") != "INACTIVE" or pool.get("MfaConfiguration") != "OFF":
    raise SystemExit("STATEFUL_VERIFICATION_COGNITO_POOL_SETTING_MISMATCH")
if set(pool.get("UsernameAttributes", [])) != {"email"}:
    raise SystemExit("STATEFUL_VERIFICATION_COGNITO_USERNAME_ATTRIBUTE_MISMATCH")
if set(pool.get("AutoVerifiedAttributes", [])) != {"email"}:
    raise SystemExit("STATEFUL_VERIFICATION_COGNITO_AUTO_VERIFIED_ATTRIBUTE_MISMATCH")
if "ClientSecret" in client:
    raise SystemExit("STATEFUL_VERIFICATION_COGNITO_CLIENT_SECRET_UNEXPECTED")
expected_flows = {"ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH"}
if set(client.get("ExplicitAuthFlows", [])) != expected_flows:
    raise SystemExit("STATEFUL_VERIFICATION_COGNITO_AUTH_FLOW_MISMATCH")
if set(client.get("SupportedIdentityProviders", [])) != {"COGNITO"}:
    raise SystemExit("STATEFUL_VERIFICATION_COGNITO_PROVIDER_MISMATCH")
if client.get("PreventUserExistenceErrors") != "ENABLED":
    raise SystemExit("STATEFUL_VERIFICATION_COGNITO_USER_EXISTENCE_BOUNDARY_MISMATCH")
PY

set +e
"$TF_EXE" -chdir="$WORK_DIR_WIN" plan \
  -input=false \
  -lock-timeout=5m \
  -parallelism=1 \
  -detailed-exitcode \
  -var-file="$STATEFUL_TFVARS_WIN" \
  -out="$PLAN_PATH_WIN" \
  -no-color >"$PLAN_LOG" 2>&1
PLAN_EXIT_CODE=$?
set -e

POST_PLAN_LOCK_STATUS="$(lock_object_status "$POST_PLAN_LOCK_ERROR_LOG")"
[[ "$POST_PLAN_LOCK_STATUS" != "lookup-failed" ]] || fail "STATEFUL_VERIFICATION_LOCK_LOOKUP_FAILED_AFTER_PLAN"

if [[ "$PLAN_EXIT_CODE" -eq 1 ]] && grep -Eq 'Error acquiring the state lock|Error locking state' "$PLAN_LOG"; then
  printf '%s\n' "TerraformNoChangePlanStatus=execution-error" >&2
  printf '%s\n' "TerraformStateLockAcquisition=failed" >&2
  printf 'PrePlanLockObjectPresent=%s\n' "$([[ "$PRE_PLAN_LOCK_STATUS" == "present" ]] && printf true || printf false)" >&2
  printf 'PostPlanLockObjectPresent=%s\n' "$([[ "$POST_PLAN_LOCK_STATUS" == "present" ]] && printf true || printf false)" >&2
  fail "STATEFUL_VERIFICATION_PLAN_LOCK_ACQUISITION_FAILED"
fi

[[ "$POST_PLAN_LOCK_STATUS" != "present" ]] || fail "STALE_STATEFUL_VERIFICATION_LOCK_OBJECT_PRESENT_AFTER_PLAN"

if [[ "$PLAN_EXIT_CODE" -eq 2 ]]; then
  "$TF_EXE" -chdir="$WORK_DIR_WIN" show -json "$PLAN_PATH_WIN" >"$PLAN_JSON" 2>>"$TERRAFORM_ERROR_LOG" ||
    fail "STATEFUL_VERIFICATION_PLAN_SUMMARY_READ_FAILED"
  PLAN_CHANGE_COUNTS="$("${PYTHON_CMD[@]}" - "$PLAN_JSON" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
resource_count = sum(
    1
    for change in plan.get("resource_changes", [])
    if change.get("mode", "managed") == "managed"
    and change.get("change", {}).get("actions", []) != ["no-op"]
)
output_count = sum(
    1
    for change in plan.get("output_changes", {}).values()
    if change.get("actions", []) != ["no-op"]
)
print(resource_count)
print(output_count)
PY
)"
  mapfile -t PLAN_CHANGE_COUNT_VALUES <<<"$PLAN_CHANGE_COUNTS"
  for index in "${!PLAN_CHANGE_COUNT_VALUES[@]}"; do
    PLAN_CHANGE_COUNT_VALUES[$index]="$(strip_trailing_carriage_return "${PLAN_CHANGE_COUNT_VALUES[$index]}")"
  done
  [[ "${#PLAN_CHANGE_COUNT_VALUES[@]}" -eq 2 ]] || fail "STATEFUL_VERIFICATION_PLAN_CHANGE_COUNT_INVALID"
  printf '%s\n' 'TerraformNoChangePlanStatus=changes-detected' >&2
  printf 'managed_resource_change_count=%s\n' "${PLAN_CHANGE_COUNT_VALUES[0]}" >&2
  printf 'output_change_count=%s\n' "${PLAN_CHANGE_COUNT_VALUES[1]}" >&2
  fail "STATEFUL_VERIFICATION_PLAN_NOT_EMPTY"
fi
[[ "$PLAN_EXIT_CODE" -eq 0 ]] || fail "STATEFUL_VERIFICATION_PLAN_FAILED"

cat >"$SUMMARY_PATH" <<EOF
StatefulDependenciesVerificationStatus=success
RepositoryHead=${ACTUAL_HEAD:0:12}
PythonCommand=${PYTHON_LABEL}
ManagedStateResourceCount=5
RequiredStateAddressCount=5
DatabaseInstanceIdentifierOutputPresent=true
DatabaseStatus=available
DatabaseEngine=mariadb
DatabaseInstanceClass=db.t4g.micro
DatabaseAllocatedStorageGb=20
DatabaseBackupRetentionDays=1
DatabaseStorageEncrypted=true
DatabasePubliclyAccessible=false
DatabaseMultiAz=false
DatabaseManagedMasterSecretMetadataPresent=true
DatabaseSecretValueReadExecuted=false
DatabaseIngressPrivateCidrsOnly=true
CognitoUserPoolVerified=true
CognitoUserPoolClientVerified=true
RemoteStateObjectPresent=true
StaleLockObjectPresent=false
TerraformNoChangePlanStatus=passed
TerraformApplyExecuted=false
TerraformDestroyExecuted=false
TerraformStateMutation=none
TerraformStateLocking=normal
TerraformStateLockReleased=true
AwsResourceMutation=none
SensitiveValuesPrinted=false
PrivateEvidenceDirectoryCreated=true
EOF
cat "$SUMMARY_PATH"
