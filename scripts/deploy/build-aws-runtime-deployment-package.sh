#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INPUT_DIR=""
OUTPUT_DIR="artifacts/aws-runtime-deployment-package"
CLUSTER_CHECK="false"
SERVER_DRY_RUN="false"

usage() {
  cat <<'USAGE'
Usage:
  scripts/deploy/build-aws-runtime-deployment-package.sh \
    --input-dir artifacts/aws-runtime-input-bundle \
    [--output-dir artifacts/aws-runtime-deployment-package] \
    [--cluster-check true|false] \
    [--server-dry-run true|false]

Purpose:
  Build a deployable private package from the AWS runtime input bundle:
  - backend-runtime-secret.yaml
  - aws-runtime-manifest.yaml
  - preflight-report.txt
  - apply-order.txt

This script renders and validates manifests. It does not run kubectl apply.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input-dir)
      INPUT_DIR="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --cluster-check)
      CLUSTER_CHECK="${2:-}"
      shift 2
      ;;
    --server-dry-run)
      SERVER_DRY_RUN="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

require_file() {
  local file_path="$1"
  local label="$2"
  if [[ -z "${file_path}" || ! -f "${file_path}" ]]; then
    echo "Missing required ${label}: ${file_path}" >&2
    exit 1
  fi
}

case "${CLUSTER_CHECK}" in
  true|false) ;;
  *)
    echo "--cluster-check must be true or false." >&2
    exit 1
    ;;
esac

case "${SERVER_DRY_RUN}" in
  true|false) ;;
  *)
    echo "--server-dry-run must be true or false." >&2
    exit 1
    ;;
esac

if [[ -z "${INPUT_DIR}" ]]; then
  echo "--input-dir is required." >&2
  usage >&2
  exit 1
fi

require_command bash
require_command grep
require_command kubectl

SECRET_ENV="${INPUT_DIR}/backend-runtime-secret.env"
MANIFEST_ENV="${INPUT_DIR}/aws-runtime-manifest.env"
require_file "${SECRET_ENV}" "backend runtime Secret env file"
require_file "${MANIFEST_ENV}" "AWS runtime manifest env file"

# shellcheck disable=SC1090
set -a
. "${MANIFEST_ENV}"
set +a

: "${BACKEND_IMAGE_URI:?BACKEND_IMAGE_URI is required in aws-runtime-manifest.env}"
: "${BACKEND_IRSA_ROLE_ARN:?BACKEND_IRSA_ROLE_ARN is required in aws-runtime-manifest.env}"
: "${KUBERNETES_NAMESPACE:?KUBERNETES_NAMESPACE is required in aws-runtime-manifest.env}"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

SECRET_MANIFEST="${OUTPUT_DIR}/backend-runtime-secret.yaml"
RUNTIME_MANIFEST="${OUTPUT_DIR}/aws-runtime-manifest.yaml"
PREFLIGHT_REPORT="${OUTPUT_DIR}/preflight-report.txt"
APPLY_ORDER="${OUTPUT_DIR}/apply-order.txt"

bash "${REPO_ROOT}/scripts/deploy/render-backend-runtime-secret.sh" \
  --env-file "${SECRET_ENV}" \
  --namespace "${KUBERNETES_NAMESPACE}" \
  --output "${SECRET_MANIFEST}"

bash "${REPO_ROOT}/scripts/deploy/render-aws-runtime-manifest.sh" \
  --image-uri "${BACKEND_IMAGE_URI}" \
  --irsa-role-arn "${BACKEND_IRSA_ROLE_ARN}" \
  --namespace "${KUBERNETES_NAMESPACE}" \
  --output "${RUNTIME_MANIFEST}"

bash "${REPO_ROOT}/scripts/deploy/aws-runtime-deploy-preflight.sh" \
  --runtime-manifest "${RUNTIME_MANIFEST}" \
  --secret-manifest "${SECRET_MANIFEST}" \
  --namespace "${KUBERNETES_NAMESPACE}" \
  --cluster-check "${CLUSTER_CHECK}" \
  --server-dry-run "${SERVER_DRY_RUN}" | tee "${PREFLIGHT_REPORT}"

cat > "${APPLY_ORDER}" <<EOF
# Generated AWS runtime deployment package
# This file intentionally keeps kubectl apply as a manual boundary.

KUBE_CONTEXT="\${KUBE_CONTEXT:?set target kube context}"
NAMESPACE="${KUBERNETES_NAMESPACE}"
SECRET_MANIFEST="${SECRET_MANIFEST}"
RUNTIME_MANIFEST="${RUNTIME_MANIFEST}"

kubectl --context "\${KUBE_CONTEXT}" create namespace "\${NAMESPACE}" || true
kubectl --context "\${KUBE_CONTEXT}" apply -f "\${SECRET_MANIFEST}"
kubectl --context "\${KUBE_CONTEXT}" apply -f "\${RUNTIME_MANIFEST}"

bash scripts/deploy/aws-runtime-rollout-smoke.sh \
  --namespace "\${NAMESPACE}" \
  --context "\${KUBE_CONTEXT}" \
  --project-id aws-runtime-smoke
EOF

cat > "${OUTPUT_DIR}/README.txt" <<EOF
AWS runtime deployment package generated.

Files:
- backend-runtime-secret.yaml: rendered Kubernetes Secret manifest
- aws-runtime-manifest.yaml: rendered backend runtime manifest
- preflight-report.txt: static or cluster preflight result
- apply-order.txt: manual apply and smoke command sequence

This package may contain private runtime values. Do not commit or upload it unless using public-safe sample data.
EOF

echo "Generated AWS runtime deployment package: ${OUTPUT_DIR}"
echo "- backend-runtime-secret.yaml"
echo "- aws-runtime-manifest.yaml"
echo "- preflight-report.txt"
echo "- apply-order.txt"
