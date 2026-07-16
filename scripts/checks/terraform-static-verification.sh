#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="${REPO_ROOT}/artifacts/terraform-static-verification"
SUMMARY="${EVIDENCE_DIR}/verification-summary.txt"
TERRAFORM_DIRS=(
  "${REPO_ROOT}/infra/terraform/runtime-contract"
  "${REPO_ROOT}/infra/terraform/envs/aws-runtime-network"
  "${REPO_ROOT}/infra/terraform/envs/backend-runtime-dependencies"
  "${REPO_ROOT}/infra/terraform/envs/backend-stateful-dependencies"
  "${REPO_ROOT}/infra/terraform/envs/eks-runtime"
  "${REPO_ROOT}/infra/terraform/envs/frontend-delivery"
)

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

require_command terraform
require_command tee

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${EVIDENCE_DIR}"
: >"${SUMMARY}"

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

printf '%s\n' \
  "terraform_static_verification=passed" \
  "terraform_directory_count=${#TERRAFORM_DIRS[@]}" \
  >>"${SUMMARY}"

cat "${SUMMARY}"
