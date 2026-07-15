#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${REPO_ROOT}/artifacts/aws-runtime-evidence-collection-verification"
FIXTURE_DIR="${ARTIFACT_DIR}/fixtures"
PACKAGE_DIR="${FIXTURE_DIR}/deployment-package"
SMOKE_DIR="${FIXTURE_DIR}/rollout-smoke"
EVIDENCE_DIR="${ARTIFACT_DIR}/evidence"

require_file() {
  local file_path="$1"
  if [[ ! -s "${file_path}" ]]; then
    echo "Expected non-empty file: ${file_path}" >&2
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

rm -rf "${ARTIFACT_DIR}"
mkdir -p "${PACKAGE_DIR}" "${SMOKE_DIR}"

cat > "${PACKAGE_DIR}/backend-runtime-secret.yaml" <<'YAML'
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: terraformers-backend-runtime-secrets
  namespace: terraformers-runtime
stringData:
  SPRING_DATASOURCE_URL: jdbc:mariadb://database.example.internal:3306/terraformers
  SPRING_DATASOURCE_USERNAME: terraformers_app
  SPRING_DATASOURCE_PASSWORD: example-password-not-a-secret
YAML

cat > "${PACKAGE_DIR}/aws-runtime-manifest.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: terraformers-backend
  namespace: terraformers-runtime
spec:
  template:
    spec:
      serviceAccountName: terraformers-backend
      containers:
        - name: terraformers-backend
          image: registry.example.internal/terraformers-backend:evidence-smoke
---
apiVersion: v1
kind: Service
metadata:
  name: terraformers-backend
  namespace: terraformers-runtime
YAML

cat > "${PACKAGE_DIR}/preflight-report.txt" <<'TEXT'
[aws-runtime-preflight] cluster checks and kubectl dry-runs skipped
[aws-runtime-preflight] verification completed
TEXT

cat > "${PACKAGE_DIR}/apply-order.txt" <<'TEXT'
# Manual boundary
kubectl --context "$KUBE_CONTEXT" apply -f backend-runtime-secret.yaml
kubectl --context "$KUBE_CONTEXT" apply -f aws-runtime-manifest.yaml
bash scripts/deploy/aws-runtime-rollout-smoke.sh --namespace terraformers-runtime --context "$KUBE_CONTEXT"
TEXT

cat > "${PACKAGE_DIR}/README.txt" <<'TEXT'
Public-safe deployment package fixture.
TEXT

cat > "${SMOKE_DIR}/rollout-status.txt" <<'TEXT'
deployment "terraformers-backend" successfully rolled out
TEXT
cat > "${SMOKE_DIR}/pods.txt" <<'TEXT'
NAME                                    READY   STATUS    RESTARTS   AGE
terraformers-backend-abc123             1/1     Running   0          1m
TEXT
cat > "${SMOKE_DIR}/endpoints.yaml" <<'YAML'
apiVersion: v1
kind: Endpoints
metadata:
  name: terraformers-backend
YAML
cat > "${SMOKE_DIR}/health.json" <<'JSON'
{"status":"UP"}
JSON
cat > "${SMOKE_DIR}/upload-response.json" <<'JSON'
{"projectId":"aws-runtime-smoke"}
JSON
cat > "${SMOKE_DIR}/project-tree.json" <<'JSON'
{"projectId":"aws-runtime-smoke","tree":[]}
JSON
cat > "${SMOKE_DIR}/main-tf-response.json" <<'JSON'
{"content":"terraform {}"}
JSON

bash "${REPO_ROOT}/scripts/deploy/collect-aws-runtime-evidence.sh" \
  --cluster-check false \
  --package-dir "${PACKAGE_DIR}" \
  --smoke-dir "${SMOKE_DIR}" \
  --output-dir "${EVIDENCE_DIR}" \
  --namespace terraformers-runtime \
  --image-uri registry.example.internal/terraformers-backend:evidence-smoke \
  --irsa-role-arn arn:aws:iam::123456789012:role/terraformers-dev-backend-irsa

require_file "${EVIDENCE_DIR}/metadata.txt"
require_file "${EVIDENCE_DIR}/evidence-checklist.txt"
require_file "${EVIDENCE_DIR}/deployment-package/manifest-sha256.txt"
require_file "${EVIDENCE_DIR}/deployment-package/preflight-report.txt"
require_file "${EVIDENCE_DIR}/deployment-package/apply-order.txt"
require_file "${EVIDENCE_DIR}/smoke/health.json"
require_file "${EVIDENCE_DIR}/smoke/upload-response.json"
require_file "${EVIDENCE_DIR}/smoke/project-tree.json"
require_file "${EVIDENCE_DIR}/smoke/main-tf-response.json"
require_file "${EVIDENCE_DIR}/kubernetes/README.txt"

assert_contains '^cluster_check=false$' "${EVIDENCE_DIR}/metadata.txt" "Metadata must record static collection mode."
assert_contains 'aws-runtime-manifest.yaml' "${EVIDENCE_DIR}/deployment-package/manifest-sha256.txt" "Evidence must hash runtime manifest."
assert_contains 'backend-runtime-secret.yaml' "${EVIDENCE_DIR}/deployment-package/manifest-sha256.txt" "Evidence must hash Secret manifest without copying it."
assert_contains 'kubectl collection skipped' "${EVIDENCE_DIR}/kubernetes/README.txt" "Static verification must not require a live cluster."
assert_contains 'No kubectl apply' "${EVIDENCE_DIR}/evidence-checklist.txt" "Checklist must preserve manual apply boundary."
assert_contains 'aws-runtime-smoke' "${EVIDENCE_DIR}/smoke/project-tree.json" "Smoke evidence must be copied."

if [[ -f "${EVIDENCE_DIR}/deployment-package/backend-runtime-secret.yaml" ]]; then
  echo "Evidence collection must not copy the Secret manifest; it should record only a hash." >&2
  exit 1
fi

echo "[aws-runtime-evidence] verification completed"
