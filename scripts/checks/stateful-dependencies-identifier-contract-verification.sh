#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUTS_TF="${REPO_ROOT}/infra/terraform/envs/backend-stateful-dependencies/outputs.tf"
NORMAL_APPLY="${REPO_ROOT}/scripts/deploy/apply-approved-stateful-dependencies.sh"
RECOVERY_APPLY="${REPO_ROOT}/scripts/deploy/apply-approved-stateful-dependencies-recovery.sh"
APPLIED_VERIFY="${REPO_ROOT}/scripts/deploy/verify-applied-stateful-dependencies.sh"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

output_block() {
  local name="$1"
  awk -v name="$name" '
    { sub(/\r$/, "", $0) }
    $1 == "output" && $2 == ("\"" name "\"") && $3 == "{" { capture = 1 }
    capture { print }
    capture && /^[[:space:]]*}[[:space:]]*$/ { exit }
  ' "$OUTPUTS_TF"
}

for command_name in awk grep; do
  command -v "$command_name" >/dev/null 2>&1 || fail "REQUIRED_COMMAND_NOT_FOUND: $command_name"
done

for required_file in "$OUTPUTS_TF" "$NORMAL_APPLY" "$RECOVERY_APPLY" "$APPLIED_VERIFY"; do
  [[ -s "$required_file" ]] || fail "STATEFUL_IDENTIFIER_CONTRACT_FILE_MISSING"
done

DATABASE_ID_BLOCK="$(output_block database_instance_id)"
DATABASE_IDENTIFIER_BLOCK="$(output_block database_instance_identifier)"

printf '%s\n' "$DATABASE_ID_BLOCK" |
  grep -Eq 'value[[:space:]]*=[[:space:]]*aws_db_instance\.backend\.id$' ||
  fail "DATABASE_INSTANCE_ID_COMPATIBILITY_CONTRACT_CHANGED"
printf '%s\n' "$DATABASE_IDENTIFIER_BLOCK" |
  grep -Eq 'value[[:space:]]*=[[:space:]]*aws_db_instance\.backend\.identifier$' ||
  fail "DATABASE_INSTANCE_IDENTIFIER_OUTPUT_INVALID"

for apply_script in "$NORMAL_APPLY" "$RECOVERY_APPLY"; do
  grep -Fq 'strip_trailing_carriage_return()' "$apply_script" ||
    fail "PYTHON_OUTPUT_CR_NORMALIZER_MISSING"
  grep -Fq "\${value%\$'\\r'}" "$apply_script" ||
    fail "PYTHON_OUTPUT_CR_NORMALIZER_INVALID"
  NORMALIZATION_BLOCK="$(awk '
    /for shell_value_name in/ { capture = 1 }
    capture { print }
    capture && /^[[:space:]]*done[[:space:]]*$/ { exit }
  ' "$apply_script")"
  printf '%s\n' "$NORMALIZATION_BLOCK" |
    grep -Fq 'strip_trailing_carriage_return "${!shell_value_name}"' ||
    fail "PYTHON_OUTPUT_CR_NORMALIZER_NOT_APPLIED"
  for shell_value_name in \
    DB_INSTANCE_IDENTIFIER \
    SG_ID \
    POOL_ID \
    CLIENT_ID \
    MASTER_SECRET_ARN; do
    printf '%s\n' "$NORMALIZATION_BLOCK" |
      grep -Eq "(^|[[:space:]\\\\])${shell_value_name}([[:space:]\\\\;]|$)" ||
      fail "PYTHON_OUTPUT_CR_NORMALIZER_VALUE_MISSING: $shell_value_name"
  done
  grep -Fq '"database_instance_id",' "$apply_script" ||
    fail "DATABASE_INSTANCE_ID_COMPATIBILITY_OUTPUT_NOT_VALIDATED"
  grep -Fq '"database_instance_identifier",' "$apply_script" ||
    fail "DATABASE_INSTANCE_IDENTIFIER_OUTPUT_NOT_VALIDATED"
  grep -Eq '\[[[:space:]]*"database_instance_identifier"[[:space:]]*\][[:space:]]*\[[[:space:]]*"value"[[:space:]]*\]' "$apply_script" ||
    fail "DATABASE_INSTANCE_IDENTIFIER_NOT_EXTRACTED"
  if grep -Eq '\[[[:space:]]*"database_instance_id"[[:space:]]*\][[:space:]]*\[[[:space:]]*"value"[[:space:]]*\]' "$apply_script"; then
    fail "DATABASE_INSTANCE_ID_EXTRACTED_AS_API_IDENTIFIER"
  fi
  grep -Fq -- '--db-instance-identifier "$DB_INSTANCE_IDENTIFIER"' "$apply_script" ||
    fail "RDS_DESCRIBE_DOES_NOT_USE_DATABASE_INSTANCE_IDENTIFIER"
  if grep -Fq -- '--db-instance-identifier "$DB_ID"' "$apply_script"; then
    fail "DATABASE_INSTANCE_ID_USED_AS_DB_INSTANCE_IDENTIFIER"
  fi
done

grep -Fq '"database_instance_identifier",' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_IDENTIFIER_OUTPUT_NOT_PARSED"
grep -Fq 'database_instance_identifier) DB_INSTANCE_IDENTIFIER="$value" ;;' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_IDENTIFIER_OUTPUT_NOT_USED"
grep -Fq 'value="$(strip_trailing_carriage_return "$value")"' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_OUTPUT_RECORD_CR_NOT_NORMALIZED"
grep -Fq 'PLAN_CHANGE_COUNT_VALUES[$index]="$(strip_trailing_carriage_return "${PLAN_CHANGE_COUNT_VALUES[$index]}")"' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_PLAN_CHANGE_COUNT_CR_NOT_NORMALIZED"
grep -Fq -- '--db-instance-identifier "$DB_INSTANCE_IDENTIFIER"' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_RDS_DESCRIBE_IDENTIFIER_INVALID"
grep -Fq -- '-detailed-exitcode' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_DETAILED_EXIT_CODE_MISSING"
grep -Fq -- '-lock-timeout=5m' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_LOCK_TIMEOUT_MISSING"
if grep -Fq -- '-lock=false' "$APPLIED_VERIFY"; then
  fail "APPLIED_VERIFY_STATE_LOCKING_DISABLED"
fi
grep -Fq 'STALE_STATEFUL_VERIFICATION_LOCK_OBJECT_PRESENT_AFTER_PLAN' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_POST_PLAN_STALE_LOCK_CHECK_MISSING"
grep -Fq 'STATEFUL_VERIFICATION_PLAN_LOCK_ACQUISITION_FAILED' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_LOCK_ACQUISITION_FAILURE_CLASSIFICATION_MISSING"
grep -Fq 'TerraformStateLocking=normal' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_NORMAL_STATE_LOCKING_SUMMARY_MISSING"
grep -Fq 'TerraformStateLockReleased=true' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_STATE_LOCK_RELEASE_SUMMARY_MISSING"
grep -Fq 'TerraformNoChangePlanStatus=passed' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_NO_CHANGE_SUCCESS_BOUNDARY_MISSING"
grep -Fq '[[ "$PLAN_EXIT_CODE" -eq 0 ]]' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_NO_CHANGE_EXIT_CODE_BOUNDARY_MISSING"
grep -Fq 'Terraformers/live-foundation' "$APPLIED_VERIFY" ||
  fail "APPLIED_VERIFY_PRIVATE_EVIDENCE_BOUNDARY_MISSING"

if grep -Eq '^[[:space:]]*"\$TF_EXE".*[[:space:]](apply|destroy)([[:space:]\\]|$)' "$APPLIED_VERIFY"; then
  fail "APPLIED_VERIFY_TERRAFORM_MUTATION_PRESENT"
fi
if grep -Eq '^[[:space:]]*"\$TF_EXE".*[[:space:]]state[[:space:]]+(rm|mv|import|push)([[:space:]\\]|$)' "$APPLIED_VERIFY"; then
  fail "APPLIED_VERIFY_TERRAFORM_STATE_MUTATION_PRESENT"
fi
if grep -Eq '^[[:space:]]*aws[[:space:]]+[^[:space:]]+[[:space:]]+(create|update|modify|put|delete)[-[:alnum:]]*' "$APPLIED_VERIFY"; then
  fail "APPLIED_VERIFY_AWS_MUTATION_PRESENT"
fi
if grep -Fq 'get-secret'"-value" "$APPLIED_VERIFY"; then
  fail "APPLIED_VERIFY_SECRET_VALUE_READ_PRESENT"
fi

printf '%s\n' \
  'stateful_dependencies_identifier_contract=passed' \
  'database_instance_id_semantics=dbi-resource-id' \
  'database_instance_identifier_semantics=db-instance-identifier' \
  'rds_describe_identifier_source=database_instance_identifier' \
  'python_output_cr_normalization=passed' \
  'applied_verification_mode=read-only' \
  'applied_verification_state_locking=normal'
