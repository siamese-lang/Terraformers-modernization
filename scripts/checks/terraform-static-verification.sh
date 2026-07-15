#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TERRAFORM_DIRS=(
  "${REPO_ROOT}/infra/terraform/runtime-contract"
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

require_command terraform

for terraform_dir in "${TERRAFORM_DIRS[@]}"; do
  echo "[terraform-static] checking ${terraform_dir#${REPO_ROOT}/}"
  cd "${terraform_dir}"
  terraform init -backend=false -input=false >/dev/null
  terraform fmt -check
  terraform validate

done

echo "[terraform-static] verification completed"
