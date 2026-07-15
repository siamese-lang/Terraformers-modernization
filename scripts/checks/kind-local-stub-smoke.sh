#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OVERLAY_DIR="${REPO_ROOT}/infra/kubernetes/overlays/local-stub"
NAMESPACE="${KIND_SMOKE_NAMESPACE:-terraformers-local}"
DEPLOYMENT="terraformers-backend"
SERVICE="terraformers-backend"
IMAGE_NAME="${KIND_SMOKE_IMAGE:-terraformers-backend:local-stub}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-terraformers-local-smoke}"
PORT_FORWARD_PID=""
PORT_FORWARD_LOG="${REPO_ROOT}/artifacts/kind-local-stub-smoke/port-forward.log"
SMOKE_OUTPUT_DIR="${REPO_ROOT}/artifacts/kind-local-stub-smoke"

cleanup() {
  if [[ -n "${PORT_FORWARD_PID}" ]] && kill -0 "${PORT_FORWARD_PID}" >/dev/null 2>&1; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-60}"
  local sleep_seconds="${3:-2}"

  for _ in $(seq 1 "${attempts}"); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep "${sleep_seconds}"
  done

  echo "Timed out waiting for ${url}" >&2
  return 1
}

json_get() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
path = sys.argv[1].split('.')
value = json.loads(sys.argv[2])
for key in path:
    if isinstance(value, list):
        value = value[int(key)]
    else:
        value = value[key]
print(value)
PY
}

require_command docker
require_command kind
require_command kubectl
require_command curl
require_command python3

mkdir -p "${SMOKE_OUTPUT_DIR}"
cd "${REPO_ROOT}"

if ! kind get clusters | grep -Fxq "${KIND_CLUSTER_NAME}"; then
  echo "[kind-smoke] creating kind cluster ${KIND_CLUSTER_NAME}"
  kind create cluster --name "${KIND_CLUSTER_NAME}"
else
  echo "[kind-smoke] reusing kind cluster ${KIND_CLUSTER_NAME}"
fi

kubectl config use-context "kind-${KIND_CLUSTER_NAME}"

echo "[kind-smoke] building backend image ${IMAGE_NAME}"
docker build -t "${IMAGE_NAME}" "${REPO_ROOT}/backend"

echo "[kind-smoke] loading image into kind cluster"
kind load docker-image "${IMAGE_NAME}" --name "${KIND_CLUSTER_NAME}"

echo "[kind-smoke] applying local-stub overlay"
kubectl apply -k "${OVERLAY_DIR}"

echo "[kind-smoke] waiting for rollout"
kubectl -n "${NAMESPACE}" rollout status deployment/"${DEPLOYMENT}" --timeout=180s
kubectl -n "${NAMESPACE}" get pods -l app.kubernetes.io/name="${DEPLOYMENT}" -o wide | tee "${SMOKE_OUTPUT_DIR}/pods.txt"

echo "[kind-smoke] starting port-forward"
kubectl -n "${NAMESPACE}" port-forward service/"${SERVICE}" 18080:80 >"${PORT_FORWARD_LOG}" 2>&1 &
PORT_FORWARD_PID="$!"
wait_for_http "http://127.0.0.1:18080/actuator/health" 60 2

curl -fsS "http://127.0.0.1:18080/actuator/health" | tee "${SMOKE_OUTPUT_DIR}/health.json"

UPLOAD_RESPONSE=$(curl -fsS -X POST "http://127.0.0.1:18080/api/upload" \
  -F "file=@${REPO_ROOT}/README.md;type=image/png;filename=local-smoke-architecture.png")
echo "${UPLOAD_RESPONSE}" | tee "${SMOKE_OUTPUT_DIR}/upload-response.json"

PROJECT_ID=$(json_get projectId "${UPLOAD_RESPONSE}")
if [[ -z "${PROJECT_ID}" ]]; then
  echo "Upload response did not include projectId" >&2
  exit 1
fi

echo "[kind-smoke] projectId=${PROJECT_ID}"
curl -fsS "http://127.0.0.1:18080/api/project-tree/${PROJECT_ID}" | tee "${SMOKE_OUTPUT_DIR}/project-tree.json"
curl -fsS "http://127.0.0.1:18080/api/projects/${PROJECT_ID}/terraform/main.tf" | tee "${SMOKE_OUTPUT_DIR}/main-tf.json"

kubectl -n "${NAMESPACE}" logs deployment/"${DEPLOYMENT}" --tail=200 > "${SMOKE_OUTPUT_DIR}/backend.log" || true

echo "[kind-smoke] local Kubernetes smoke completed"
