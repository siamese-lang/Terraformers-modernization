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

validate_rendered_manifest() {
  local manifest="$1"
  local label="$2"

  if [[ ! -s "${manifest}" ]]; then
    echo "Rendered Kubernetes package is empty: ${label}" >&2
    exit 1
  fi

  awk -v label="${label}" '
    BEGIN {
      document_count = 0
      has_api_version = 0
      has_kind = 0
      has_metadata = 0
      has_name = 0
    }
    function validate_document() {
      if (has_api_version || has_kind || has_metadata || has_name) {
        document_count++
        if (!has_api_version || !has_kind || !has_metadata || !has_name) {
          printf("Rendered package %s document %d is missing apiVersion, kind, metadata, or metadata.name\n", label, document_count) > "/dev/stderr"
          exit 1
        }
      }
      has_api_version = 0
      has_kind = 0
      has_metadata = 0
      has_name = 0
    }
    /^---[[:space:]]*$/ {
      validate_document()
      next
    }
    /^apiVersion:[[:space:]]*/ { has_api_version = 1 }
    /^kind:[[:space:]]*/ { has_kind = 1 }
    /^metadata:[[:space:]]*$/ { has_metadata = 1 }
    /^[[:space:]]+name:[[:space:]]*/ {
      if (has_metadata) {
        has_name = 1
      }
    }
    END {
      validate_document()
      if (document_count == 0) {
        printf("Rendered package %s contains no Kubernetes documents\n", label) > "/dev/stderr"
        exit 1
      }
      printf("package=%s documents=%d\n", label, document_count)
    }
  ' "${manifest}" >>"${EVIDENCE_DIR}/kubernetes-render-summary.txt"

  assert_contains '^kind: ConfigMap$' "${manifest}" "Rendered package ${label} must contain the runtime ConfigMap."
  assert_contains '^kind: ServiceAccount$' "${manifest}" "Rendered package ${label} must contain the backend ServiceAccount."
  assert_contains '^kind: Service$' "${manifest}" "Rendered package ${label} must contain the backend Service."
  assert_contains '^kind: Deployment$' "${manifest}" "Rendered package ${label} must contain the backend Deployment."
  assert_not_contains '^kind: Secret$' "${manifest}" "Rendered deployment packages must not contain committed Secret resources."
  assert_contains 'runAsNonRoot: true' "${manifest}" "Rendered Deployment must enforce non-root execution."
  assert_contains 'allowPrivilegeEscalation: false' "${manifest}" "Rendered Deployment must block privilege escalation."
  assert_contains 'startupProbe:' "${manifest}" "Rendered Deployment must include a startup probe."
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
require_command awk

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${EVIDENCE_DIR}"

cd "${FRONTEND_DIR}"
if [[ ! -f package-lock.json ]]; then
  echo "[predeployment] frontend lockfile is absent; generating current dependency resolution"
  npm install \
    --package-lock-only \
    --ignore-scripts \
    --legacy-peer-deps \
    --no-audit \
    --no-fund
  cp package-lock.json "${EVIDENCE_DIR}/frontend-package-lock.generated.json"
  printf '%s\n' 'generated-from-current-package-json' >"${EVIDENCE_DIR}/frontend-lockfile-status.txt"
else
  echo "[predeployment] using committed frontend lockfile"
  cp package-lock.json "${EVIDENCE_DIR}/frontend-package-lock.committed.json"
  printf '%s\n' 'committed-lockfile' >"${EVIDENCE_DIR}/frontend-lockfile-status.txt"
fi

node --version >"${EVIDENCE_DIR}/frontend-node-version.txt"
npm --version >"${EVIDENCE_DIR}/frontend-npm-version.txt"

node <<'NODE' >"${EVIDENCE_DIR}/frontend-ajv-lock-resolution.txt"
const fs = require('fs');
const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const lock = JSON.parse(fs.readFileSync('package-lock.json', 'utf8'));
const packages = lock.packages || {};
const ajvVersion = packages['node_modules/ajv']?.version;
const keywordsVersion = packages['node_modules/ajv-keywords']?.version;
const declaredAjv = packageJson.devDependencies?.ajv;
const declaredKeywords = packageJson.devDependencies?.['ajv-keywords'];

console.log(`declared_ajv=${declaredAjv || ''}`);
console.log(`declared_ajv_keywords=${declaredKeywords || ''}`);
console.log(`resolved_root_ajv=${ajvVersion || ''}`);
console.log(`resolved_root_ajv_keywords=${keywordsVersion || ''}`);

if (!ajvVersion?.startsWith('8.')) {
  throw new Error(`Root AJV must resolve to major version 8 for ajv-keywords 5, found: ${ajvVersion || 'missing'}`);
}
if (!keywordsVersion?.startsWith('5.')) {
  throw new Error(`Root ajv-keywords must resolve to major version 5, found: ${keywordsVersion || 'missing'}`);
}
NODE

echo "[predeployment] installing frontend dependencies from lockfile"
npm ci --legacy-peer-deps --no-audit --no-fund

node <<'NODE' >"${EVIDENCE_DIR}/frontend-ajv-runtime-resolution.txt"
const ajvPackage = require('ajv/package.json');
const keywordsPackage = require('ajv-keywords/package.json');
const codegenPath = require.resolve('ajv/dist/compile/codegen');

console.log(`runtime_ajv=${ajvPackage.version}`);
console.log(`runtime_ajv_keywords=${keywordsPackage.version}`);
console.log(`codegen_module=${codegenPath}`);

if (!ajvPackage.version.startsWith('8.')) {
  throw new Error(`Runtime root AJV must be major version 8, found: ${ajvPackage.version}`);
}
if (!keywordsPackage.version.startsWith('5.')) {
  throw new Error(`Runtime root ajv-keywords must be major version 5, found: ${keywordsPackage.version}`);
}
NODE

npm ls ajv ajv-keywords --all >"${EVIDENCE_DIR}/frontend-ajv-dependency-tree.txt" 2>&1 || true

echo "[predeployment] building frontend production bundle"
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

echo "[predeployment] rendering Kubernetes deployment packages without cluster discovery"
kubectl version --client --output=yaml >"${EVIDENCE_DIR}/kubectl-client-version.yaml"
kubectl kustomize "${K8S_BASE_DIR}" >"${EVIDENCE_DIR}/kubernetes-base.yaml"
kubectl kustomize "${K8S_LOCAL_DIR}" >"${EVIDENCE_DIR}/kubernetes-local-stub.yaml"
kubectl kustomize "${K8S_AWS_DIR}" >"${EVIDENCE_DIR}/kubernetes-aws-runtime-template.yaml"

validate_rendered_manifest "${EVIDENCE_DIR}/kubernetes-base.yaml" "base"
validate_rendered_manifest "${EVIDENCE_DIR}/kubernetes-local-stub.yaml" "local-stub"
validate_rendered_manifest "${EVIDENCE_DIR}/kubernetes-aws-runtime-template.yaml" "aws-runtime-template"

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
  'frontend_lock_resolution=passed' \
  'frontend_ajv_compatibility=passed' \
  'frontend_bundle=passed' \
  'backend_image_build=passed' \
  'backend_container_health=passed' \
  'backend_runtime_uid=10001' \
  'kubernetes_offline_render_validation=passed' \
  >"${EVIDENCE_DIR}/verification-summary.txt"

echo "[predeployment] package verification completed"
