#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/reconcile-live-foundation-state-isolated.sh \
    --expected-head SHA

This command creates a fresh Terraform data directory outside the repository,
reinitializes the existing S3 backend without migrating or writing state,
verifies that the pinned AWS provider can return its schema, and then runs the
read-only foundation state reconciliation.
EOF
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
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

for command_name in git cygpath rm mkdir grep sed; do
  command -v "$command_name" >/dev/null 2>&1 || fail "REQUIRED_COMMAND_NOT_FOUND: $command_name"
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
FOUNDATION_DIR="$REPO_ROOT/infra/terraform/bootstrap/aws-live-foundation"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
TF_EXE="$(cygpath -u "$LOCALAPPDATA")/Programs/Terraform/1.15.8/terraform.exe"
BACKEND_CONFIG="$PRIVATE_DIR/foundation.backend.hcl"
ISOLATED_TF_DATA_DIR="$PRIVATE_DIR/foundation-reconcile-tfdata"
ISOLATED_CLI_CONFIG="$PRIVATE_DIR/foundation-reconcile.tfrc"
SCHEMA_OUTPUT="$PRIVATE_DIR/foundation-provider-schema.json"
SCHEMA_LOG="$PRIVATE_DIR/foundation-provider-schema.log"

[[ -x "$TF_EXE" ]] || fail "TERRAFORM_1_15_8_NOT_FOUND"
[[ -f "$BACKEND_CONFIG" ]] || fail "FOUNDATION_BACKEND_CONFIG_NOT_FOUND"
[[ -f "$FOUNDATION_DIR/.terraform.lock.hcl" ]] || fail "FOUNDATION_LOCK_FILE_NOT_FOUND"
grep -Fq 'version     = "5.100.0"' "$FOUNDATION_DIR/.terraform.lock.hcl" || fail "AWS_PROVIDER_LOCK_MISMATCH"

cd "$REPO_ROOT"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}

ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"

TERRAFORM_VERSION="$($TF_EXE version | sed -n '1p')"
[[ "$TERRAFORM_VERSION" == "Terraform v1.15.8" ]] || fail "TERRAFORM_VERSION_MISMATCH: $TERRAFORM_VERSION"

mkdir -p "$PRIVATE_DIR"
rm -rf "$ISOLATED_TF_DATA_DIR"
mkdir -p "$ISOLATED_TF_DATA_DIR"

cat > "$ISOLATED_CLI_CONFIG" <<'EOF'
disable_checkpoint = true
EOF

rm -f "$SCHEMA_OUTPUT" "$SCHEMA_LOG"

BACKEND_CONFIG_WIN="$(cygpath -am "$BACKEND_CONFIG")"
ISOLATED_TF_DATA_DIR_WIN="$(cygpath -am "$ISOLATED_TF_DATA_DIR")"
ISOLATED_CLI_CONFIG_WIN="$(cygpath -am "$ISOLATED_CLI_CONFIG")"
SCHEMA_LOG_WIN="$(cygpath -am "$SCHEMA_LOG")"

export TF_DATA_DIR="$ISOLATED_TF_DATA_DIR_WIN"
export TF_CLI_CONFIG_FILE="$ISOLATED_CLI_CONFIG_WIN"
export TF_IN_AUTOMATION=1
unset TF_PLUGIN_CACHE_DIR || true

cd "$FOUNDATION_DIR"

"$TF_EXE" init \
  -input=false \
  -reconfigure \
  -lockfile=readonly \
  -backend-config="$BACKEND_CONFIG_WIN"

set +e
TF_LOG=DEBUG TF_LOG_PATH="$SCHEMA_LOG_WIN" \
  "$TF_EXE" providers schema -json > "$SCHEMA_OUTPUT" 2>/dev/null
SCHEMA_EXIT_CODE=$?
set -e

if [[ "$SCHEMA_EXIT_CODE" -ne 0 ]]; then
  rm -f "$SCHEMA_OUTPUT"
  printf '%s\n' \
    "PROVIDER_SCHEMA_LOAD_FAILED" \
    "StateMigrationRerunRequired=false" \
    "RemoteStateWriteAttempted=false" \
    "ProviderSchemaLogCreated=true" >&2
  exit "$SCHEMA_EXIT_CODE"
fi

[[ -s "$SCHEMA_OUTPUT" ]] || fail "PROVIDER_SCHEMA_OUTPUT_EMPTY"
grep -Fq 'registry.terraform.io/hashicorp/aws' "$SCHEMA_OUTPUT" || fail "AWS_PROVIDER_SCHEMA_MISSING"

rm -f "$SCHEMA_OUTPUT"

cd "$REPO_ROOT"
bash scripts/deploy/migrate-live-foundation-state.sh \
  --expected-head "$EXPECTED_HEAD" \
  --reconcile-existing-remote

printf '%s\n' \
  "ProviderRuntimeIsolation=success" \
  "ProviderSchemaLoaded=true" \
  "TerraformDataDirectory=private-isolated" \
  "RemoteStateWriteAttempted=false"
