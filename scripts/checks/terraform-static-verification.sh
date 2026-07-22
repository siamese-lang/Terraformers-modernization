#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="${REPO_ROOT}/artifacts/terraform-static-verification"
SUMMARY="${EVIDENCE_DIR}/verification-summary.txt"
STATEFUL_IDENTIFIER_CHECK="${REPO_ROOT}/scripts/checks/stateful-dependencies-identifier-contract-verification.sh"
TERRAFORM_DIRS=(
  "${REPO_ROOT}/infra/terraform/runtime-contract"
  "${REPO_ROOT}/infra/terraform/bootstrap/aws-live-foundation"
  "${REPO_ROOT}/infra/terraform/envs/aws-runtime-network"
  "${REPO_ROOT}/infra/terraform/envs/backend-runtime-dependencies"
  "${REPO_ROOT}/infra/terraform/envs/backend-stateful-dependencies"
  "${REPO_ROOT}/infra/terraform/envs/eks-runtime"
  "${REPO_ROOT}/infra/terraform/envs/frontend-delivery"
  "${REPO_ROOT}/infra/terraform/envs/rag-runtime"
)
TEARDOWN_OVERRIDE_FILES=(
  "${REPO_ROOT}/infra/terraform/envs/frontend-delivery/zz-runtime-teardown-static_override.tf"
  "${REPO_ROOT}/infra/terraform/envs/rag-runtime/zz-runtime-teardown-static_override.tf"
  "${REPO_ROOT}/infra/terraform/envs/backend-stateful-dependencies/zz-runtime-teardown-static_override.tf"
  "${REPO_ROOT}/infra/terraform/envs/backend-runtime-dependencies/zz-runtime-teardown-static_override.tf"
)

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

cleanup_teardown_overrides() {
  rm -f "${TEARDOWN_OVERRIDE_FILES[@]}"
}

trap cleanup_teardown_overrides EXIT

require_command terraform
require_command tee
require_command bash

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${EVIDENCE_DIR}"
: >"${SUMMARY}"

bash "${STATEFUL_IDENTIFIER_CHECK}" 2>&1 |
  tee "${EVIDENCE_DIR}/stateful-dependencies-identifier-contract.log"
printf '%s\n' 'stateful_dependencies_identifier_contract=passed' >>"${SUMMARY}"

for terraform_dir in "${TERRAFORM_DIRS[@]}"; do
  relative_dir="${terraform_dir#${REPO_ROOT}/}"
  log_name="$(printf '%s' "${relative_dir}" | tr '/ ' '__').log"
  log_path="${EVIDENCE_DIR}/${log_name}"

  {
    echo "[terraform-static] checking ${relative_dir}"
    cd "${terraform_dir}"
    terraform init -backend=false -input=false
    terraform fmt -check -diff
    terraform validate
    echo "terraform_directory=${relative_dir} status=passed"
  } 2>&1 | tee "${log_path}"

  printf 'terraform_directory=%s status=passed\n' "${relative_dir}" >>"${SUMMARY}"
done

cat > "${TEARDOWN_OVERRIDE_FILES[0]}" <<'EOF'
resource "aws_s3_bucket" "frontend" {
  force_destroy = true
}
EOF

cat > "${TEARDOWN_OVERRIDE_FILES[1]}" <<'EOF'
resource "aws_s3_bucket" "corpus" {
  force_destroy = true
}
EOF

cat > "${TEARDOWN_OVERRIDE_FILES[2]}" <<'EOF'
resource "aws_db_instance" "backend" {
  skip_final_snapshot      = true
  delete_automated_backups = true
  deletion_protection      = false
}
EOF

cat > "${TEARDOWN_OVERRIDE_FILES[3]}" <<'EOF'
resource "aws_ecr_repository" "backend" {
  force_delete = true
}

resource "aws_s3_bucket" "uploads" {
  force_destroy = true
}

resource "aws_s3_bucket" "results" {
  force_destroy = true
}

resource "aws_secretsmanager_secret" "backend_runtime" {
  recovery_window_in_days = 0
}
EOF

for override_file in "${TEARDOWN_OVERRIDE_FILES[@]}"; do
  override_dir="$(dirname "${override_file}")"
  relative_dir="${override_dir#${REPO_ROOT}/}"
  log_name="$(printf '%s' "${relative_dir}" | tr '/ ' '__')__runtime_teardown_override.log"
  {
    echo "[terraform-static] validating runtime teardown override in ${relative_dir}"
    terraform -chdir="${override_dir}" fmt -check -diff "$(basename "${override_file}")"
    terraform -chdir="${override_dir}" validate
    echo "runtime_teardown_override=${relative_dir} status=passed"
  } 2>&1 | tee "${EVIDENCE_DIR}/${log_name}"
  printf 'runtime_teardown_override=%s status=passed\n' "${relative_dir}" >>"${SUMMARY}"
done

cleanup_teardown_overrides
trap - EXIT

printf '%s\n' \
  "terraform_static_verification=passed" \
  "terraform_cli_minimum=1.15.0" \
  "terraform_directory_count=${#TERRAFORM_DIRS[@]}" \
  "runtime_teardown_override_count=${#TEARDOWN_OVERRIDE_FILES[@]}" \
  >>"${SUMMARY}"

cat "${SUMMARY}"
