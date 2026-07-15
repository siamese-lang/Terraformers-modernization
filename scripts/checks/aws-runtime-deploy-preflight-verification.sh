#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${REPO_ROOT}/artifacts/aws-runtime-deploy-preflight"
RUNTIME_MANIFEST="${ARTIFACT_DIR}/aws-runtime-manifest.yaml"
SECRET_MANIFEST="${ARTIFACT_DIR}/backend-runtime-secret.yaml"
BAD_MANIFEST="${ARTIFACT_DIR}/bad-runtime-manifest.yaml"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

assert_contains() {
  local pattern="$1"
  local file_path="$2"
  local message="$3"
  if ! grep -E -q "${pattern}" "${file_path}"; then
    echo "${message}" >&2
    echo "Expected pattern: ${pattern}" >&2
    exit 1
  fi
}

require_command kubectl
require_command grep
require_command cp
require_command sed

rm -rf "${ARTIFACT_DIR}"
mkdir -p "${ARTIFACT_DIR}"

echo "[aws-runtime-deploy-preflight] rendering runtime manifest"
bash "${REPO_ROOT}/scripts/deploy/render-aws-runtime-manifest.sh" \
  --image-uri "registry.example.internal/terraformers-backend:preflight-smoke" \
  --irsa-role-arn "arn:aws:iam:::role/terraformers-backend-irsa-sample" \
  --namespace "terraformers-runtime" \
  --output "${RUNTIME_MANIFEST}"

echo "[aws-runtime-deploy-preflight] rendering Secret manifest"
bash "${REPO_ROOT}/scripts/deploy/render-backend-runtime-secret.sh" \
  --env-file "${REPO_ROOT}/infra/kubernetes/runtime-secret.env.example" \
  --namespace "terraformers-runtime" \
  --output "${SECRET_MANIFEST}"

echo "[aws-runtime-deploy-preflight] running static preflight"
bash "${REPO_ROOT}/scripts/deploy/aws-runtime-deploy-preflight.sh" \
  --runtime-manifest "${RUNTIME_MANIFEST}" \
  --secret-manifest "${SECRET_MANIFEST}" \
  --namespace "terraformers-runtime" \
  --cluster-check false \
  --server-dry-run false

assert_contains 'registry.example.internal/terraformers-backend:preflight-smoke' "${RUNTIME_MANIFEST}" "Rendered manifest must contain sample image."
assert_contains 'arn:aws:iam:::role/terraformers-backend-irsa-sample' "${RUNTIME_MANIFEST}" "Rendered manifest must contain sample IRSA annotation."
assert_contains 'name: terraformers-backend-runtime-secrets' "${SECRET_MANIFEST}" "Rendered Secret manifest must contain runtime Secret name."

cp "${RUNTIME_MANIFEST}" "${BAD_MANIFEST}"
sed -i.bak 's#registry.example.internal/terraformers-backend:preflight-smoke#registry.example.com/terraformers-backend:immutable-tag#g' "${BAD_MANIFEST}"

if bash "${REPO_ROOT}/scripts/deploy/aws-runtime-deploy-preflight.sh" \
  --runtime-manifest "${BAD_MANIFEST}" \
  --secret-manifest "${SECRET_MANIFEST}" \
  --namespace "terraformers-runtime" \
  --cluster-check false \
  --server-dry-run false >/tmp/aws-runtime-preflight-bad.log 2>&1; then
  echo "Preflight must reject placeholder runtime image values." >&2
  exit 1
fi

grep -q 'placeholder image values' /tmp/aws-runtime-preflight-bad.log

echo "[aws-runtime-deploy-preflight] verification completed"
