#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/deploy/aws-runtime-rollout-smoke.sh \
    [--namespace terraformers-runtime] \
    [--context kube-context] \
    [--project-id aws-runtime-smoke]

Purpose:
  Verify a deployed AWS runtime backend after manifests have been applied manually.
  This script does not apply manifests and does not expose production traffic.

Checks:
  - Deployment rollout completed
  - backend pods are Ready
  - /actuator/health responds through port-forward
  - POST /api/upload multipart file upload creates project metadata through the deployed service
  - GET /api/project-tree/{projectId} works
  - GET /api/projects/{projectId}/terraform/main.tf works
USAGE
}

NAMESPACE="terraformers-runtime"
KUBE_CONTEXT=""
PROJECT_ID="aws-runtime-smoke"
SERVICE_NAME="terraformers-backend"
DEPLOYMENT_NAME="terraformers-backend"
LOCAL_PORT="18080"
PORT_FORWARD_PID=""
ARTIFACT_DIR="artifacts/aws-runtime-rollout-smoke"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --context)
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    --project-id)
      PROJECT_ID="$2"
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

kubectl_cmd() {
  if [[ -n "${KUBE_CONTEXT}" ]]; then
    kubectl --context "${KUBE_CONTEXT}" "$@"
  else
    kubectl "$@"
  fi
}

cleanup() {
  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

require_command kubectl
require_command curl
require_command grep

mkdir -p "${ARTIFACT_DIR}"

printf '[aws-runtime-smoke] kube context: '
kubectl_cmd config current-context

echo "[aws-runtime-smoke] waiting for deployment rollout"
kubectl_cmd -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT_NAME}" --timeout=180s | tee "${ARTIFACT_DIR}/rollout-status.txt"

echo "[aws-runtime-smoke] collecting pod status"
kubectl_cmd -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=terraformers-backend -o wide | tee "${ARTIFACT_DIR}/pods.txt"
kubectl_cmd -n "${NAMESPACE}" get endpoints "${SERVICE_NAME}" -o yaml > "${ARTIFACT_DIR}/endpoints.yaml"

if ! grep -q 'Running' "${ARTIFACT_DIR}/pods.txt"; then
  echo "No Running backend pod found." >&2
  exit 1
fi

echo "[aws-runtime-smoke] opening port-forward"
kubectl_cmd -n "${NAMESPACE}" port-forward "service/${SERVICE_NAME}" "${LOCAL_PORT}:8080" > "${ARTIFACT_DIR}/port-forward.log" 2>&1 &
PORT_FORWARD_PID="$!"
sleep 5

BASE_URL="http://127.0.0.1:${LOCAL_PORT}"
SMOKE_FILE="${ARTIFACT_DIR}/AWS Runtime Smoke.png"
printf 'fake image bytes for aws runtime smoke\n' > "${SMOKE_FILE}"

echo "[aws-runtime-smoke] checking actuator health"
curl -fsS "${BASE_URL}/actuator/health" | tee "${ARTIFACT_DIR}/health.json"

echo "[aws-runtime-smoke] creating smoke project through multipart /api/upload"
curl -fsS \
  -X POST \
  -F "file=@${SMOKE_FILE};type=image/png" \
  "${BASE_URL}/api/upload" | tee "${ARTIFACT_DIR}/upload-response.json"

echo "[aws-runtime-smoke] reading project tree"
curl -fsS "${BASE_URL}/api/project-tree/${PROJECT_ID}" | tee "${ARTIFACT_DIR}/project-tree.json"

echo "[aws-runtime-smoke] reading Terraform draft"
curl -fsS "${BASE_URL}/api/projects/${PROJECT_ID}/terraform/main.tf" | tee "${ARTIFACT_DIR}/main-tf-response.json"

grep -q "${PROJECT_ID}" "${ARTIFACT_DIR}/project-tree.json"
grep -q 'content' "${ARTIFACT_DIR}/main-tf-response.json"

echo "[aws-runtime-smoke] verification completed"
