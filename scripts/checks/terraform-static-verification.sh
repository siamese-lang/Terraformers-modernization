#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TERRAFORM_DIRS=(
  "${REPO_ROOT}/infra/terraform/runtime-contract"
  "${REPO_ROOT}/infra/terraform/envs/aws-runtime-network"
  "${REPO_ROOT}/infra/terraform/envs/backend-runtime-dependencies"
  "${REPO_ROOT}/infra/terraform/envs/backend-stateful-dependencies"
  "${REPO_ROOT}/infra/terraform/envs/eks-runtime"
)

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

run_step() {
  local label="$1"
  shift

  local log_file
  log_file="$(mktemp)"

  if ! "$@" >"${log_file}" 2>&1; then
    echo "[terraform-static] ${label} failed" >&2
    cat "${log_file}" >&2
    rm -f "${log_file}"
    exit 1
  fi

  rm -f "${log_file}"
}

require_command terraform

for terraform_dir in "${TERRAFORM_DIRS[@]}"; do
  echo "[terraform-static] checking ${terraform_dir#${REPO_ROOT}/}"
  cd "${terraform_dir}"

  run_step "terraform init for ${terraform_dir#${REPO_ROOT}/}" \
    terraform init -backend=false -input=false
  run_step "terraform fmt for ${terraform_dir#${REPO_ROOT}/}" \
    terraform fmt -check -diff
  run_step "terraform validate for ${terraform_dir#${REPO_ROOT}/}" \
    terraform validate

done

echo "[terraform-static] verification completed"
