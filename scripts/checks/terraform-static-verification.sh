#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${REPO_ROOT}/artifacts/terraform-static-verification"
SUMMARY_LOG="${ARTIFACT_DIR}/terraform-static.log"
TERRAFORM_DIRS=(
  "${REPO_ROOT}/infra/terraform/runtime-contract"
  "${REPO_ROOT}/infra/terraform/envs/aws-runtime-network"
  "${REPO_ROOT}/infra/terraform/envs/backend-runtime-dependencies"
  "${REPO_ROOT}/infra/terraform/envs/backend-stateful-dependencies"
  "${REPO_ROOT}/infra/terraform/envs/eks-runtime"
)

mkdir -p "${ARTIFACT_DIR}"
: > "${SUMMARY_LOG}"

log() {
  echo "$@" | tee -a "${SUMMARY_LOG}"
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log "Required command not found: ${command_name}"
    exit 1
  fi
}

run_step() {
  local label="$1"
  shift

  local log_file
  log_file="$(mktemp)"

  if ! "$@" >"${log_file}" 2>&1; then
    log "[terraform-static] ${label} failed"
    cat "${log_file}" | tee -a "${SUMMARY_LOG}" >&2
    rm -f "${log_file}"
    exit 1
  fi

  log "[terraform-static] ${label} passed"
  rm -f "${log_file}"
}

require_command terraform

for terraform_dir in "${TERRAFORM_DIRS[@]}"; do
  log "[terraform-static] checking ${terraform_dir#${REPO_ROOT}/}"
  cd "${terraform_dir}"

  run_step "terraform init for ${terraform_dir#${REPO_ROOT}/}" \
    terraform init -backend=false -input=false
  run_step "terraform fmt for ${terraform_dir#${REPO_ROOT}/}" \
    terraform fmt -check -diff
  run_step "terraform validate for ${terraform_dir#${REPO_ROOT}/}" \
    terraform validate

done

log "[terraform-static] verification completed"
