#!/usr/bin/env bash
set -Eeuo pipefail

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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-head)
      [[ $# -ge 2 ]] || fail "EXPECTED_HEAD_VALUE_MISSING"
      EXPECTED_HEAD="$2"
      shift 2
      ;;
    -h|--help)
      printf '%s\n' 'Usage: bash scripts/deploy/diagnose-live-foundation-state.sh --expected-head SHA'
      exit 0
      ;;
    *)
      fail "UNKNOWN_ARGUMENT: $1"
      ;;
  esac
done

[[ -n "$EXPECTED_HEAD" ]] || fail "EXPECTED_HEAD_REQUIRED"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FOUNDATION_DIR="${REPO_ROOT}/infra/terraform/bootstrap/aws-live-foundation"
PRIVATE_DIR="$(cygpath -u "$LOCALAPPDATA")/Terraformers/live-foundation"
TF_EXE="$(cygpath -u "$LOCALAPPDATA")/Programs/Terraform/1.15.8/terraform.exe"
STATE_BACKUP="${PRIVATE_DIR}/foundation.local-pre-migration.tfstate"
REMOTE_STATE="${PRIVATE_DIR}/foundation.remote-diagnostic.tfstate"
DIAGNOSTIC_JSON="${PRIVATE_DIR}/foundation.check-results-diagnostic.json"

for command_name in git cygpath; do
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
[[ -f "$STATE_BACKUP" ]] || fail "FOUNDATION_STATE_BACKUP_NOT_FOUND"

cd "$REPO_ROOT"
[[ -z "$(git status --porcelain)" ]] || fail "WORKING_TREE_NOT_CLEAN"
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"

mkdir -p "$PRIVATE_DIR"
cd "$FOUNDATION_DIR"
"$TF_EXE" state pull > "$REMOTE_STATE"

"${PYTHON_CMD[@]}" - "$STATE_BACKUP" "$REMOTE_STATE" "$DIAGNOSTIC_JSON" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

local_path = Path(sys.argv[1])
remote_path = Path(sys.argv[2])
diagnostic_path = Path(sys.argv[3])
local = json.loads(local_path.read_text(encoding="utf-8"))
remote = json.loads(remote_path.read_text(encoding="utf-8"))

if local.get("resources") != remote.get("resources"):
    raise SystemExit("REMOTE_STATE_RESOURCES_PAYLOAD_MISMATCH")
if local.get("outputs") != remote.get("outputs"):
    raise SystemExit("REMOTE_STATE_OUTPUTS_PAYLOAD_MISMATCH")


def kind(value):
    if value is None:
        return "null"
    if isinstance(value, list):
        return "list"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def count(value):
    if value is None:
        return 0
    if isinstance(value, (list, dict)):
        return len(value)
    return 1


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def normalize_top_level(value):
    if value is None:
        return []
    if isinstance(value, list):
        return sorted(value, key=canonical)
    return value


def collect_key_values(value, target_key):
    found = []
    if isinstance(value, dict):
        for key, nested in value.items():
            if key == target_key and isinstance(nested, (str, int, float, bool)):
                found.append(str(nested))
            found.extend(collect_key_values(nested, target_key))
    elif isinstance(value, list):
        for nested in value:
            found.extend(collect_key_values(nested, target_key))
    return found


def collect_addresses(value):
    keys = {"config_addr", "object_addr", "to_display", "address"}
    found = []
    if isinstance(value, dict):
        for key, nested in value.items():
            if key in keys and isinstance(nested, str):
                found.append(nested)
            found.extend(collect_addresses(nested))
    elif isinstance(value, list):
        for nested in value:
            found.extend(collect_addresses(nested))
    return found

local_checks = local.get("check_results")
remote_checks = remote.get("check_results")
exact = local_checks == remote_checks
local_normalized = normalize_top_level(local_checks)
remote_normalized = normalize_top_level(remote_checks)
order_only = (not exact) and local_normalized == remote_normalized
null_empty_equivalent = (
    not exact
    and local_checks in (None, [])
    and remote_checks in (None, [])
)

local_statuses = sorted(set(collect_key_values(local_checks, "status")))
remote_statuses = sorted(set(collect_key_values(remote_checks, "status")))
local_addresses = sorted(set(collect_addresses(local_checks)))
remote_addresses = sorted(set(collect_addresses(remote_checks)))

result = {
    "resources_exact": True,
    "outputs_exact": True,
    "local_serial": local.get("serial"),
    "remote_serial": remote.get("serial"),
    "lineage_preserved": local.get("lineage") == remote.get("lineage"),
    "local_check_kind": kind(local_checks),
    "remote_check_kind": kind(remote_checks),
    "local_check_count": count(local_checks),
    "remote_check_count": count(remote_checks),
    "local_check_digest": digest(local_checks),
    "remote_check_digest": digest(remote_checks),
    "check_results_exact": exact,
    "check_results_order_only_difference": order_only,
    "check_results_null_empty_equivalent": null_empty_equivalent,
    "local_statuses": local_statuses,
    "remote_statuses": remote_statuses,
    "local_addresses": local_addresses,
    "remote_addresses": remote_addresses,
}
diagnostic_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

print("StateDiagnosticStatus=complete")
print("ResourcesPayloadExact=true")
print("OutputsPayloadExact=true")
print(f"LocalSerial={result['local_serial']}")
print(f"RemoteSerial={result['remote_serial']}")
print(f"LineagePreserved={str(result['lineage_preserved']).lower()}")
print(f"LocalCheckResultsKind={result['local_check_kind']}")
print(f"RemoteCheckResultsKind={result['remote_check_kind']}")
print(f"LocalCheckResultsCount={result['local_check_count']}")
print(f"RemoteCheckResultsCount={result['remote_check_count']}")
print(f"CheckResultsExact={str(exact).lower()}")
print(f"CheckResultsOrderOnlyDifference={str(order_only).lower()}")
print(f"CheckResultsNullEmptyEquivalent={str(null_empty_equivalent).lower()}")
print("LocalCheckStatuses=" + (",".join(local_statuses) if local_statuses else "none"))
print("RemoteCheckStatuses=" + (",".join(remote_statuses) if remote_statuses else "none"))
print(f"LocalCheckAddressCount={len(local_addresses)}")
print(f"RemoteCheckAddressCount={len(remote_addresses)}")
print("AwsMutation=none")
PY

printf '%s\n' "PythonCommand=${PYTHON_LABEL}" "DiagnosticFileCreated=true"
