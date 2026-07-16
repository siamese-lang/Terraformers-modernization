#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
FRONTEND_DIR="${REPO_ROOT}/frontend"
K8S_BASE_DIR="${REPO_ROOT}/infra/kubernetes/base"
K8S_LOCAL_DIR="${REPO_ROOT}/infra/kubernetes/overlays/local-stub"
K8S_AWS_DIR="${REPO_ROOT}/infra/kubernetes/overlays/aws-runtime-template"
EVIDENCE_DIR="${REPO_ROOT}/artifacts/predeployment"
IMAGE_TAG="terraformers-backend:predeployment"
LOCAL_IMAGE_TAG="terraformers-backend:local-stub"
CONTAINER_NAME="terraformers-backend-predeployment"
HOST_PORT="${PREDEPLOYMENT_BACKEND_PORT:-18081}"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

assert_contains() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! grep -E -q "${pattern}" "${file}"; then
    echo "${message}" >&2
    echo "Expected pattern: ${pattern}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if grep -E -q "${pattern}" "${file}"; then
    echo "${message}" >&2
    echo "Matched pattern: ${pattern}" >&2
    exit 1
  fi
}

cleanup() {
  local status=$?
  trap - EXIT
  if docker ps -a --format '{{.Names}}' | grep -Fxq "${CONTAINER_NAME}"; then
    docker logs "${CONTAINER_NAME}" >"${EVIDENCE_DIR}/backend-container.log" 2>&1 || true
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi
  exit "${status}"
}
trap cleanup EXIT

require_command docker
require_command node
require_command npm
require_command kubectl
require_command curl
require_command grep

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${EVIDENCE_DIR}"

echo "[predeployment] building deterministic frontend bundle"
cd "${FRONTEND_DIR}"
npm ci
npm run build

test -f build/index.html
find build -type f -printf '%P\n' | sort >"${EVIDENCE_DIR}/frontend-build-files.txt"
assert_not_contains \
  'REACT_APP_ANALYSIS_PROJECT_ID|REACT_APP_ANALYSIS_SOURCE_BUCKET|REACT_APP_ANALYSIS_SOURCE_KEY' \
  "${FRONTEND_DIR}/.env.example" \
  "Obsolete client-controlled analysis identifiers must not return to the frontend environment contract."

echo "[predeployment] building backend runtime image"
cd "${REPO_ROOT}"
docker build \
  --file backend/Dockerfile \
  --tag "${IMAGE_TAG}" \
  --tag "${LOCAL_IMAGE_TAG}" \
  backend

docker image inspect "${IMAGE_TAG}" >"${EVIDENCE_DIR}/backend-image-inspect.json"
docker history --no-trunc "${IMAGE_TAG}" >"${EVIDENCE_DIR}/backend-image-history.txt"

image_user="$(docker image inspect --format '{{.Config.User}}' "${IMAGE_TAG}")"
if [[ "${image_user}" != "appuser" && "${image_user}" != "10001" ]]; then
  echo "Backend image must declare appuser or UID 10001, found: ${image_user}" >&2
  exit 1
fi

docker image inspect --format '{{json .Config.Healthcheck}}' "${IMAGE_TAG}" \
  >"${EVIDENCE_DIR}/backend-image-healthcheck.json"
assert_not_contains '^null$' "${EVIDENCE_DIR}/backend-image-healthcheck.json" "Backend image must declare a healthcheck."

echo "[predeployment] starting backend image with local adapters"
docker run -d \
  --name "${CONTAINER_NAME}" \
  --publish "127.0.0.1:${HOST_PORT}:8080" \
  --env SPRING_PROFILES_ACTIVE=local \
  "${IMAGE_TAG}" >/dev/null

healthy=false
for attempt in $(seq 1 60); do
  if ! docker inspect --format '{{.State.Running}}' "${CONTAINER_NAME}" | grep -qx true; then
    echo "Backend container exited before becoming healthy." >&2
    docker logs "${CONTAINER_NAME}" >&2 || true
    exit 1
  fi

  if curl --fail --silent --show-error \
      "http://127.0.0.1:${HOST_PORT}/actuator/health" \
      >"${EVIDENCE_DIR}/backend-health.json" 2>/dev/null; then
    healthy=true
    break
  fi

  sleep 2
done

if [[ "${healthy}" != "true" ]]; then
  echo "Backend container did not become healthy." >&2
  docker logs "${CONTAINER_NAME}" >&2 || true
  exit 1
fi

docker exec "${CONTAINER_NAME}" id -u >"${EVIDENCE_DIR}/backend-runtime-uid.txt"
grep -qx '10001' "${EVIDENCE_DIR}/backend-runtime-uid.txt"
docker exec "${CONTAINER_NAME}" terraform version >"${EVIDENCE_DIR}/backend-terraform-version.txt"
docker exec "${CONTAINER_NAME}" sh -c 'test -r /app/app.jar'
docker logs "${CONTAINER_NAME}" >"${EVIDENCE_DIR}/backend-container.log" 2>&1

echo "[predeployment] rendering Kubernetes deployment packages"
kubectl kustomize "${K8S_BASE_DIR}" >"${EVIDENCE_DIR}/kubernetes-base.yaml"
kubectl kustomize "${K8S_LOCAL_DIR}" >"${EVIDENCE_DIR}/kubernetes-local-stub.yaml"
kubectl kustomize "${K8S_AWS_DIR}" >"${EVIDENCE_DIR}/kubernetes-aws-runtime-template.yaml"

for manifest in \
  "${EVIDENCE_DIR}/kubernetes-base.yaml" \
  "${EVIDENCE_DIR}/kubernetes-local-stub.yaml" \
  "${EVIDENCE_DIR}/kubernetes-aws-runtime-template.yaml"; do
  kubectl create --dry-run=client --validate=false -f "${manifest}" >/dev/null
  assert_not_contains '^kind: Secret$' "${manifest}" "Rendered deployment packages must not contain committed Secret resources."
  assert_contains 'runAsNonRoot: true' "${manifest}" "Rendered Deployment must enforce non-root execution."
  assert_contains 'allowPrivilegeEscalation: false' "${manifest}" "Rendered Deployment must block privilege escalation."
  assert_contains 'startupProbe:' "${manifest}" "Rendered Deployment must include a startup probe."
done

assert_contains \
  'image: terraformers-backend:local-stub' \
  "${EVIDENCE_DIR}/kubernetes-local-stub.yaml" \
  "Local overlay must reference the image built by this verification."
assert_contains \
  'imagePullPolicy: Never' \
  "${EVIDENCE_DIR}/kubernetes-local-stub.yaml" \
  "Local overlay must not pull an unverified image."
assert_contains \
  'image: registry\.example\.com/terraformers-backend:immutable-tag' \
  "${EVIDENCE_DIR}/kubernetes-aws-runtime-template.yaml" \
  "AWS runtime template must retain the explicit immutable image replacement contract."
assert_not_contains \
  'image: .*:latest([[:space:]]|$)' \
  "${EVIDENCE_DIR}/kubernetes-aws-runtime-template.yaml" \
  "AWS runtime template must not use the mutable latest tag."
assert_contains \
  'SPRING_PROFILES_ACTIVE: prod' \
  "${EVIDENCE_DIR}/kubernetes-aws-runtime-template.yaml" \
  "AWS runtime template must use the production profile."

printf '%s\n' \
  'frontend_bundle=passed' \
  'backend_image_build=passed' \
  'backend_container_health=passed' \
  'backend_runtime_uid=10001' \
  'kubernetes_client_dry_run=passed' \
  >"${EVIDENCE_DIR}/verification-summary.txt"

echo "[predeployment] package verification completed"
