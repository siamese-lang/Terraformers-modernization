#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${REPO_ROOT}/artifacts/aws-runtime-live-rollout-readiness-verification"
PACKAGE_DIR="${ARTIFACT_DIR}/deployment-package-fixture"
OUTPUT_DIR="${ARTIFACT_DIR}/readiness-output"
BAD_PACKAGE_DIR="${ARTIFACT_DIR}/bad-loadbalancer-package"
BAD_OUTPUT="${ARTIFACT_DIR}/bad-loadbalancer-output.txt"
IMAGE_URI="123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend:readiness-smoke"
IRSA_ROLE_ARN="arn:aws:iam::123456789012:role/terraformers-dev-backend-irsa"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
}

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

assert_not_contains() {
  local pattern="$1"
  local file_path="$2"
  local message="$3"
  if grep -E -q "${pattern}" "${file_path}"; then
    echo "${message}" >&2
    echo "Matched pattern: ${pattern}" >&2
    exit 1
  fi
}

require_command bash
require_command grep
require_command sha256sum
require_command find
require_command cp

rm -rf "${ARTIFACT_DIR}"
mkdir -p "${PACKAGE_DIR}"

cat > "${PACKAGE_DIR}/backend-runtime-secret.yaml" <<'YAML'
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: terraformers-backend-runtime-secrets
  namespace: terraformers-runtime
data:
  SPRING_DATASOURCE_PASSWORD: ZXhhbXBsZS1wYXNzd29yZA==
YAML

cat > "${PACKAGE_DIR}/aws-runtime-manifest.yaml" <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: terraformers-backend
  namespace: terraformers-runtime
  annotations:
    eks.amazonaws.com/role-arn: ${IRSA_ROLE_ARN}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: terraformers-backend
  namespace: terraformers-runtime
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: terraformers-backend
  template:
    metadata:
      labels:
        app.kubernetes.io/name: terraformers-backend
    spec:
      serviceAccountName: terraformers-backend
      containers:
        - name: terraformers-backend
          image: ${IMAGE_URI}
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: prod
          envFrom:
            - secretRef:
                name: terraformers-backend-runtime-secrets
---
apiVersion: v1
kind: Service
metadata:
  name: terraformers-backend
  namespace: terraformers-runtime
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: terraformers-backend
  ports:
    - name: http
      port: 8080
      targetPort: 8080
YAML

cat > "${PACKAGE_DIR}/preflight-report.txt" <<'TXT'
[aws-runtime-preflight] cluster checks and kubectl dry-runs skipped
[aws-runtime-preflight] verification completed
TXT

cat > "${PACKAGE_DIR}/apply-order.txt" <<'TXT'
# Generated AWS runtime deployment package
# This file intentionally keeps kubectl apply as a manual boundary.

KUBE_CONTEXT="${KUBE_CONTEXT:?set target kube context}"
NAMESPACE="terraformers-runtime"
SECRET_MANIFEST="/tmp/terraformers-deployment-package/backend-runtime-secret.yaml"
RUNTIME_MANIFEST="/tmp/terraformers-deployment-package/aws-runtime-manifest.yaml"

kubectl --context "${KUBE_CONTEXT}" create namespace "${NAMESPACE}" || true
kubectl --context "${KUBE_CONTEXT}" apply -f "${SECRET_MANIFEST}"
kubectl --context "${KUBE_CONTEXT}" apply -f "${RUNTIME_MANIFEST}"

bash scripts/deploy/aws-runtime-rollout-smoke.sh \
  --namespace "${NAMESPACE}" \
  --context "${KUBE_CONTEXT}" \
  --project-id aws-runtime-smoke
TXT

cat > "${PACKAGE_DIR}/README.txt" <<'TXT'
AWS runtime deployment package generated.
TXT

echo "[aws-runtime-readiness] checking valid package"
bash "${REPO_ROOT}/scripts/deploy/check-aws-runtime-live-rollout-readiness.sh" \
  --package-dir "${PACKAGE_DIR}" \
  --output-dir "${OUTPUT_DIR}" \
  --namespace terraformers-runtime \
  --cluster-check false \
  --expected-image-uri "${IMAGE_URI}" \
  --expected-irsa-role-arn "${IRSA_ROLE_ARN}"

require_file "${OUTPUT_DIR}/readiness-report.txt"
require_file "${OUTPUT_DIR}/rollout-readiness-checklist.txt"
require_file "${OUTPUT_DIR}/cluster-readiness.txt"
require_file "${OUTPUT_DIR}/deployment-package/package-sha256.txt"
require_file "${OUTPUT_DIR}/deployment-package/preflight-report.txt"
require_file "${OUTPUT_DIR}/deployment-package/apply-order.txt"
require_file "${OUTPUT_DIR}/deployment-package/README.txt"

assert_contains 'status=ready-for-manual-apply' "${OUTPUT_DIR}/readiness-report.txt" "Readiness report must mark the package ready for manual apply."
assert_contains 'terraform_apply_executed=false' "${OUTPUT_DIR}/readiness-report.txt" "Readiness report must confirm Terraform apply was not executed."
assert_contains 'kubectl_apply_executed=false' "${OUTPUT_DIR}/readiness-report.txt" "Readiness report must confirm kubectl apply was not executed."
assert_contains 'public_ingress_allowed=false' "${OUTPUT_DIR}/readiness-report.txt" "Readiness report must keep public ingress out of the first rollout."
assert_contains 'adapter_enablement_allowed=false' "${OUTPUT_DIR}/readiness-report.txt" "Readiness report must keep adapters disabled for first rollout."
assert_contains 'backend-runtime-secret.yaml' "${OUTPUT_DIR}/deployment-package/package-sha256.txt" "Secret manifest must be represented by hash."
assert_contains 'aws-runtime-manifest.yaml' "${OUTPUT_DIR}/deployment-package/package-sha256.txt" "Runtime manifest must be represented by hash."
assert_contains '\[aws-runtime-readiness\] cluster checks skipped' "${OUTPUT_DIR}/cluster-readiness.txt" "Static verification must skip cluster checks."
assert_contains 'After manual apply, run scripts/deploy/aws-runtime-rollout-smoke.sh' "${OUTPUT_DIR}/rollout-readiness-checklist.txt" "Checklist must include the existing smoke path."
assert_contains 'After smoke succeeds, run scripts/deploy/collect-aws-runtime-evidence.sh' "${OUTPUT_DIR}/rollout-readiness-checklist.txt" "Checklist must include the existing evidence collection path."

if find "${OUTPUT_DIR}" -type f -name 'backend-runtime-secret.yaml' | grep -q .; then
  echo "Readiness artifact must not copy backend-runtime-secret.yaml." >&2
  exit 1
fi

cp -R "${PACKAGE_DIR}" "${BAD_PACKAGE_DIR}"
printf '\ntype: LoadBalancer\n' >> "${BAD_PACKAGE_DIR}/aws-runtime-manifest.yaml"

set +e
bash "${REPO_ROOT}/scripts/deploy/check-aws-runtime-live-rollout-readiness.sh" \
  --package-dir "${BAD_PACKAGE_DIR}" \
  --output-dir "${ARTIFACT_DIR}/bad-output" \
  --cluster-check false \
  >"${BAD_OUTPUT}" 2>&1
bad_status=$?
set -e

if [[ ${bad_status} -eq 0 ]]; then
  echo "Readiness check must reject public LoadBalancer exposure." >&2
  exit 1
fi

assert_contains 'must not expose public ingress or LoadBalancer service' "${BAD_OUTPUT}" "LoadBalancer rejection must be explicit."
assert_not_contains 'terraform apply' "${OUTPUT_DIR}/readiness-report.txt" "Readiness report must not instruct Terraform apply."

echo "[aws-runtime-readiness] verification completed"
