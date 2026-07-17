#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/migrate-live-foundation-state.sh \
    --expected-head SHA \
    [--execute-migration | --reconcile-existing-remote]

Modes:
  no mode flag                  Preflight only. No S3 state write.
  --execute-migration           Migrate verified local state to S3.
  --reconcile-existing-remote   Verify an already-created remote state after a
                                migration that stopped during post-checks.

Reconciliation never overwrites or pushes state. It requires exact resource and
output payloads, order-insensitive equivalence of passing check results, valid
lineage/serial semantics, and a no-change plan without refresh.
EOF
}

fail() {
  echo "$1" >&2
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
EXECUTE_MIGRATION=false
RECONCILE_EXISTING_REMOTE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-head)
      [[ $# -ge 2 ]] || fail "EXPECTED_HEAD_VALUE_MISSING"
      EXPECTED_HEAD="$2"
      shift 2
      ;;
    --execute-migration)
      EXECUTE_MIGRATION=true
      shift
      ;;
    --reconcile-existing-remote)
      RECONCILE_EXISTING_REMOTE=true
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
if [[ "$EXECUTE_MIGRATION" == true && "$RECONCILE_EXISTING_REMOTE" == true ]]; then
  fail "MIGRATION_MODE_CONFLICT"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FOUNDATION_DIR="${REPO_ROOT}/infra/terraform/bootstrap/aws-live-foundation"
PRIVATE_DIR="$(cygpath -u "$LOCALAPPDATA")/Terraformers/live-foundation"
TF_EXE="$(cygpath -u "$LOCALAPPDATA")/Programs/Terraform/1.15.8/terraform.exe"
TFVARS_PATH="${PRIVATE_DIR}/foundation.tfvars"
LOCAL_STATE="${FOUNDATION_DIR}/terraform.tfstate"
STATE_BACKUP="${PRIVATE_DIR}/foundation.local-pre-migration.tfstate"
STATE_BACKUP_DIGEST="${STATE_BACKUP}.sha256"
BACKEND_CONFIG="${PRIVATE_DIR}/foundation.backend.hcl"
LOCAL_INVENTORY="${PRIVATE_DIR}/foundation.local-pre-migration.inventory.json"
REMOTE_STATE="${PRIVATE_DIR}/foundation.remote-post-migration.tfstate"
RECONCILIATION_RESULT="${PRIVATE_DIR}/foundation.state-reconciliation.json"
POST_PLAN="${PRIVATE_DIR}/foundation.post-migration.tfplan"
POST_PLAN_LOG="${PRIVATE_DIR}/foundation.post-migration-plan.log"

for command_name in git aws sha256sum cygpath sed sort grep awk tr; do
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

[[ -x "$TF_EXE" ]] || fail "TERRAFORM_1_15_8_NOT_FOUND"
[[ -f "$TFVARS_PATH" ]] || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
[[ -f "${FOUNDATION_DIR}/versions.tf" ]] || fail "FOUNDATION_VERSIONS_FILE_NOT_FOUND"
grep -Eq 'backend[[:space:]]+"s3"[[:space:]]*\{' "${FOUNDATION_DIR}/versions.tf" || fail "S3_BACKEND_DECLARATION_MISSING"

cd "$REPO_ROOT"
[[ -z "$(git status --porcelain)" ]] || fail "WORKING_TREE_NOT_CLEAN"

ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"

EXPECTED_ACCOUNT="$(read_tfvar_string expected_aws_account_id)"
STATE_BUCKET="$(read_tfvar_string state_bucket_name)"
STATE_PREFIX="$(read_tfvar_string state_prefix)"
AWS_REGION="$(read_tfvar_string aws_region)"

[[ "$EXPECTED_ACCOUNT" =~ ^[0-9]{12}$ ]] || fail "EXPECTED_ACCOUNT_ID_INVALID"
[[ -n "$STATE_BUCKET" ]] || fail "STATE_BUCKET_NAME_MISSING"
[[ -n "$STATE_PREFIX" ]] || fail "STATE_PREFIX_MISSING"
[[ -n "$AWS_REGION" ]] || fail "AWS_REGION_MISSING"

STATE_PREFIX="${STATE_PREFIX#/}"
STATE_PREFIX="${STATE_PREFIX%/}"
STATE_KEY="${STATE_PREFIX}/bootstrap/terraform.tfstate"
LOCK_KEY="${STATE_KEY}.tflock"

CALLER_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
[[ "$CALLER_ACCOUNT" == "$EXPECTED_ACCOUNT" ]] || fail "AWS_ACCOUNT_MISMATCH"

TERRAFORM_VERSION="$($TF_EXE version | head -n 1)"
[[ "$TERRAFORM_VERSION" == "Terraform v1.15.8" ]] || fail "TERRAFORM_VERSION_MISMATCH"

VERSIONING="$(aws s3api get-bucket-versioning --bucket "$STATE_BUCKET" --query Status --output text)"
[[ "$VERSIONING" == "Enabled" ]] || fail "VERSIONING_CHECK_FAILED"

PUBLIC_BLOCK="$(aws s3api get-public-access-block --bucket "$STATE_BUCKET" --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,BlockPublicPolicy,IgnorePublicAcls,RestrictPublicBuckets]' --output text | tr '\t' ' ')"
[[ "$PUBLIC_BLOCK" == "True True True True" ]] || fail "PUBLIC_ACCESS_BLOCK_CHECK_FAILED"

ENCRYPTION="$(aws s3api get-bucket-encryption --bucket "$STATE_BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)"
[[ "$ENCRYPTION" == "AES256" ]] || fail "ENCRYPTION_CHECK_FAILED"

mkdir -p "$PRIVATE_DIR"

SOURCE_STATE=""
if [[ "$RECONCILE_EXISTING_REMOTE" == true ]]; then
  [[ -f "$STATE_BACKUP" ]] || fail "FOUNDATION_STATE_BACKUP_NOT_FOUND"
  [[ -f "$STATE_BACKUP_DIGEST" ]] || fail "FOUNDATION_STATE_BACKUP_DIGEST_NOT_FOUND"
  SOURCE_STATE="$STATE_BACKUP"
elif [[ -f "$LOCAL_STATE" ]]; then
  SOURCE_STATE="$LOCAL_STATE"
elif [[ -f "$STATE_BACKUP" ]]; then
  SOURCE_STATE="$STATE_BACKUP"
else
  fail "FOUNDATION_SOURCE_STATE_NOT_FOUND"
fi

SOURCE_DIGEST="$(sha256sum "$SOURCE_STATE" | awk '{print $1}')"

if [[ -f "$STATE_BACKUP" ]]; then
  BACKUP_DIGEST="$(sha256sum "$STATE_BACKUP" | awk '{print $1}')"
  [[ "$BACKUP_DIGEST" == "$SOURCE_DIGEST" ]] || fail "LOCAL_STATE_BACKUP_DIGEST_MISMATCH"
else
  cp -f "$SOURCE_STATE" "$STATE_BACKUP"
  BACKUP_DIGEST="$SOURCE_DIGEST"
fi

if [[ -f "$STATE_BACKUP_DIGEST" ]]; then
  RECORDED_BACKUP_DIGEST="$(awk 'NR==1 {print $1}' "$STATE_BACKUP_DIGEST")"
  [[ "$RECORDED_BACKUP_DIGEST" =~ ^[0-9a-fA-F]{64}$ ]] || fail "LOCAL_STATE_BACKUP_RECORDED_DIGEST_INVALID"
  [[ "${RECORDED_BACKUP_DIGEST,,}" == "${BACKUP_DIGEST,,}" ]] || fail "LOCAL_STATE_BACKUP_RECORDED_DIGEST_MISMATCH"
else
  sha256sum "$STATE_BACKUP" > "$STATE_BACKUP_DIGEST"
fi

"${PYTHON_CMD[@]}" - "$STATE_BACKUP" "$LOCAL_INVENTORY" <<'PY'
import json
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
inventory_path = Path(sys.argv[2])
state = json.loads(state_path.read_text(encoding="utf-8"))

addresses = []
for resource in state.get("resources", []):
    if resource.get("mode") != "managed":
        continue
    prefix = resource.get("module")
    base = f"{resource['type']}.{resource['name']}"
    if prefix:
        base = f"{prefix}.{base}"
    instances = resource.get("instances", [])
    if not instances:
        addresses.append(base)
        continue
    for instance in instances:
        index = instance.get("index_key")
        if index is None:
            addresses.append(base)
        elif isinstance(index, int):
            addresses.append(f"{base}[{index}]")
        else:
            addresses.append(f"{base}[{json.dumps(index)}]")

expected = sorted([
    "aws_iam_role.terraform_plan",
    "aws_iam_role_policy.terraform_state_access",
    "aws_iam_role_policy_attachment.terraform_plan_read_only",
    "aws_s3_bucket.terraform_state",
    "aws_s3_bucket_ownership_controls.terraform_state",
    "aws_s3_bucket_policy.terraform_state",
    "aws_s3_bucket_public_access_block.terraform_state",
    "aws_s3_bucket_server_side_encryption_configuration.terraform_state",
    "aws_s3_bucket_versioning.terraform_state",
])
actual = sorted(addresses)
if actual != expected:
    print("[expected managed addresses]", file=sys.stderr)
    print("\n".join(expected), file=sys.stderr)
    print("[actual managed addresses]", file=sys.stderr)
    print("\n".join(actual), file=sys.stderr)
    raise SystemExit("FOUNDATION_LOCAL_STATE_SET_MISMATCH")

inventory = {
    "lineage": state.get("lineage"),
    "serial": state.get("serial"),
    "managed_addresses": actual,
}
inventory_path.write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
PY

cat > "$BACKEND_CONFIG" <<EOF
bucket       = "${STATE_BUCKET}"
key          = "${STATE_KEY}"
region       = "${AWS_REGION}"
encrypt      = true
use_lockfile = true
EOF

REMOTE_STATE_EXISTS=false
if aws s3api head-object --bucket "$STATE_BUCKET" --key "$STATE_KEY" >/dev/null 2>&1; then
  REMOTE_STATE_EXISTS=true
fi

if [[ "$EXECUTE_MIGRATION" != true && "$RECONCILE_EXISTING_REMOTE" != true ]]; then
  printf '%s\n' \
    "StateMigrationPreflight=passed" \
    "RepositoryHead=${ACTUAL_HEAD:0:12}" \
    "PythonCommand=${PYTHON_LABEL}" \
    "LocalStateBackupVerified=true" \
    "LocalManagedResourceCount=9" \
    "BackendConfigCreated=true" \
    "BackendKey=${STATE_KEY}" \
    "RemoteStateAlreadyExists=${REMOTE_STATE_EXISTS}" \
    "StateMigrationExecuted=false" \
    "AwsMutation=none"
  exit 0
fi

cd "$FOUNDATION_DIR"
BACKEND_CONFIG_WIN="$(cygpath -aw "$BACKEND_CONFIG")"
TFVARS_PATH_WIN="$(cygpath -aw "$TFVARS_PATH")"
POST_PLAN_WIN="$(cygpath -aw "$POST_PLAN")"

MIGRATION_PERFORMED=false
if [[ "$EXECUTE_MIGRATION" == true ]]; then
  [[ "$REMOTE_STATE_EXISTS" == false ]] || fail "REMOTE_BOOTSTRAP_STATE_ALREADY_EXISTS_USE_RECONCILIATION"

  "$TF_EXE" init \
    -input=false \
    -migrate-state \
    -force-copy \
    -backend-config="$BACKEND_CONFIG_WIN"

  MIGRATION_PERFORMED=true
else
  [[ "$REMOTE_STATE_EXISTS" == true ]] || fail "REMOTE_BOOTSTRAP_STATE_NOT_FOUND"

  "$TF_EXE" init \
    -input=false \
    -reconfigure \
    -lockfile=readonly \
    -backend-config="$BACKEND_CONFIG_WIN"
fi

"$TF_EXE" state pull > "$REMOTE_STATE"

RECONCILIATION_STATUS="$(
  "${PYTHON_CMD[@]}" - "$STATE_BACKUP" "$REMOTE_STATE" "$RECONCILIATION_RESULT" <<'PY'
import json
import sys
from pathlib import Path

local_path = Path(sys.argv[1])
remote_path = Path(sys.argv[2])
result_path = Path(sys.argv[3])
local = json.loads(local_path.read_text(encoding="utf-8"))
remote = json.loads(remote_path.read_text(encoding="utf-8"))


def managed_addresses(state):
    addresses = []
    for resource in state.get("resources", []):
        if resource.get("mode") != "managed":
            continue
        prefix = resource.get("module")
        base = f"{resource['type']}.{resource['name']}"
        if prefix:
            base = f"{prefix}.{base}"
        instances = resource.get("instances", [])
        if not instances:
            addresses.append(base)
            continue
        for instance in instances:
            index = instance.get("index_key")
            if index is None:
                addresses.append(base)
            elif isinstance(index, int):
                addresses.append(f"{base}[{index}]")
            else:
                addresses.append(f"{base}[{json.dumps(index)}]")
    return sorted(addresses)


def canonical_check_items(value):
    if value is None:
        return []
    if not isinstance(value, list):
        raise SystemExit("REMOTE_STATE_CHECK_RESULTS_KIND_MISMATCH")
    return sorted(
        json.dumps(item, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        for item in value
    )


def collect_statuses(value):
    statuses = []

    def walk(item):
        if isinstance(item, dict):
            for key, child in item.items():
                if key == "status" and isinstance(child, str):
                    statuses.append(child.lower())
                walk(child)
        elif isinstance(item, list):
            for child in item:
                walk(child)

    walk(value)
    return sorted(set(statuses))


local_addresses = managed_addresses(local)
remote_addresses = managed_addresses(remote)
if remote_addresses != local_addresses:
    raise SystemExit("REMOTE_STATE_ADDRESS_SET_MISMATCH")

if remote.get("resources") != local.get("resources"):
    raise SystemExit("REMOTE_STATE_RESOURCES_PAYLOAD_MISMATCH")
if remote.get("outputs") != local.get("outputs"):
    raise SystemExit("REMOTE_STATE_OUTPUTS_PAYLOAD_MISMATCH")

local_checks = local.get("check_results")
remote_checks = remote.get("check_results")
local_canonical_checks = canonical_check_items(local_checks)
remote_canonical_checks = canonical_check_items(remote_checks)
if remote_canonical_checks != local_canonical_checks:
    raise SystemExit("REMOTE_STATE_CHECK_RESULTS_SEMANTIC_MISMATCH")

check_statuses = collect_statuses(remote_checks)
if check_statuses and check_statuses != ["pass"]:
    raise SystemExit("REMOTE_STATE_CHECK_RESULTS_NOT_ALL_PASSING")

check_results_exact = remote_checks == local_checks
check_results_status = "exact" if check_results_exact else "order-only"

local_serial = int(local.get("serial", -1))
remote_serial = int(remote.get("serial", -1))
if local_serial < 0:
    raise SystemExit("LOCAL_STATE_SERIAL_INVALID")

lineage_preserved = remote.get("lineage") == local.get("lineage")
if lineage_preserved:
    if remote_serial < local_serial:
        raise SystemExit("REMOTE_STATE_SERIAL_REGRESSION")
    serial_status = "non-regressing"
else:
    if remote_serial < 1:
        raise SystemExit("REMOTE_STATE_REBASED_SERIAL_INVALID")
    serial_status = "reset-valid"

result = {
    "managed_addresses": remote_addresses,
    "resources_exact": True,
    "outputs_exact": True,
    "check_results_exact": check_results_exact,
    "check_results_order_only": not check_results_exact,
    "check_statuses": check_statuses,
    "payload_semantically_equivalent": True,
    "lineage_preserved": lineage_preserved,
    "lineage_rebased": not lineage_preserved,
    "local_serial": local_serial,
    "remote_serial": remote_serial,
    "serial_status": serial_status,
}
result_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(
    "|".join(
        [
            "preserved" if lineage_preserved else "rebased",
            serial_status,
            check_results_status,
        ]
    )
)
PY
)"

IFS='|' read -r LINEAGE_STATUS SERIAL_STATUS CHECK_RESULTS_STATUS <<< "$RECONCILIATION_STATUS"

aws s3api head-object --bucket "$STATE_BUCKET" --key "$STATE_KEY" >/dev/null
STATE_VERSION_COUNT="$(aws s3api list-object-versions --bucket "$STATE_BUCKET" --prefix "$STATE_KEY" --query "length(Versions[?Key=='${STATE_KEY}'])" --output text)"
[[ "$STATE_VERSION_COUNT" =~ ^[0-9]+$ ]] || fail "STATE_VERSION_COUNT_INVALID"
(( STATE_VERSION_COUNT >= 1 )) || fail "REMOTE_STATE_VERSION_MISSING"

set +e
"$TF_EXE" plan \
  -input=false \
  -lock=false \
  -refresh=false \
  -detailed-exitcode \
  -var-file="$TFVARS_PATH_WIN" \
  -out="$POST_PLAN_WIN" \
  > "$POST_PLAN_LOG" 2>&1
PLAN_EXIT_CODE=$?
set -e

if [[ "$PLAN_EXIT_CODE" -eq 2 ]]; then
  cat "$POST_PLAN_LOG" >&2
  fail "POST_MIGRATION_PLAN_HAS_CHANGES"
elif [[ "$PLAN_EXIT_CODE" -ne 0 ]]; then
  cat "$POST_PLAN_LOG" >&2
  fail "POST_MIGRATION_PLAN_FAILED"
fi

if aws s3api head-object --bucket "$STATE_BUCKET" --key "$LOCK_KEY" >/dev/null 2>&1; then
  fail "STALE_NATIVE_LOCK_OBJECT_PRESENT"
fi

mapfile -t REMOTE_ADDRESSES < <("$TF_EXE" state list | grep -v '^data\.' | sort)
[[ "${#REMOTE_ADDRESSES[@]}" -eq 9 ]] || fail "REMOTE_MANAGED_STATE_COUNT_MISMATCH"

FINAL_STATUS="$(git -C "$REPO_ROOT" status --porcelain)"
[[ -z "$FINAL_STATUS" ]] || fail "WORKING_TREE_CHANGED_DURING_MIGRATION"

case "$LINEAGE_STATUS" in
  preserved)
    LINEAGE_PRESERVED=true
    LINEAGE_REBASED=false
    ;;
  rebased)
    LINEAGE_PRESERVED=false
    LINEAGE_REBASED=true
    ;;
  *)
    fail "STATE_LINEAGE_STATUS_INVALID"
    ;;
esac

case "$SERIAL_STATUS" in
  non-regressing)
    SERIAL_NON_REGRESSING=true
    SERIAL_RESET_VALID=false
    ;;
  reset-valid)
    SERIAL_NON_REGRESSING=false
    SERIAL_RESET_VALID=true
    ;;
  *)
    fail "STATE_SERIAL_STATUS_INVALID"
    ;;
esac

case "$CHECK_RESULTS_STATUS" in
  exact)
    CHECK_RESULTS_EXACT=true
    CHECK_RESULTS_ORDER_ONLY=false
    ;;
  order-only)
    CHECK_RESULTS_EXACT=false
    CHECK_RESULTS_ORDER_ONLY=true
    ;;
  *)
    fail "STATE_CHECK_RESULTS_STATUS_INVALID"
    ;;
esac

if [[ "$MIGRATION_PERFORMED" == true ]]; then
  STATUS="success"
  AWS_MUTATION="state-object-only"
else
  STATUS="success-reconciled"
  AWS_MUTATION="none"
fi

printf '%s\n' \
  "StateMigrationStatus=${STATUS}" \
  "RepositoryHead=${ACTUAL_HEAD:0:12}" \
  "PythonCommand=${PYTHON_LABEL}" \
  "RemoteBackend=s3-native-lockfile" \
  "RemoteStateObjectPresent=true" \
  "RemoteStateVersionCount=${STATE_VERSION_COUNT}" \
  "ManagedStateResourceCount=${#REMOTE_ADDRESSES[@]}" \
  "StateResourcesExact=true" \
  "StateOutputsExact=true" \
  "StateCheckResultsExact=${CHECK_RESULTS_EXACT}" \
  "StateCheckResultsOrderOnly=${CHECK_RESULTS_ORDER_ONLY}" \
  "StateCheckStatuses=pass" \
  "StatePayloadSemanticallyEquivalent=true" \
  "StateLineagePreserved=${LINEAGE_PRESERVED}" \
  "StateLineageRebased=${LINEAGE_REBASED}" \
  "StateSerialNonRegressing=${SERIAL_NON_REGRESSING}" \
  "StateSerialResetValid=${SERIAL_RESET_VALID}" \
  "PostMigrationPlanNoChanges=true" \
  "StaleLockObjectPresent=false" \
  "LocalStateBackupPreserved=true" \
  "AwsMutation=${AWS_MUTATION}"
