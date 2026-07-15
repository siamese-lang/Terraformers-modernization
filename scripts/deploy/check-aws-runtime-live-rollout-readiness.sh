#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/deploy/check-aws-runtime-live-rollout-readiness.sh \
    --package-dir /tmp/terraformers-deployment-package \
    [--output-dir artifacts/aws-runtime-live-rollout-readiness] \
    [--namespace terraformers-runtime] \
    [--context kube-context] \
    [--cluster-check true|false] \
    [--expected-image-uri <immutable-image-uri>] \
    [--expected-irsa-role-arn <iam-role-arn>]

Purpose:
  Run the final readiness gate before a manual AWS runtime rollout.
  This script verifies the deployment package and optional target cluster context.
  It does not run terraform apply, terraform destroy, or kubectl apply.
USAGE
}

PACKAGE_DIR=""
OUTPUT_DIR="artifacts/aws-runtime-live-rollout-readiness"
NAMESPACE="terraformers-runtime"
KUBE_CONTEXT=""
CLUSTER_CHECK="false"
EXPECTED_IMAGE_URI=""
EXPECTED_IRSA_ROLE_ARN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-dir)
      PACKAGE_DIR="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --namespace)
      NAMESPACE="${2:-}"
      shift 2
      ;;
    --context)
      KUBE_CONTEXT="${2:-}"
      shift 2
      ;;
    --cluster-check)
      CLUSTER_CHECK="${2:-}"
      shift 2
      ;;
    --expected-image-uri)
      EXPECTED_IMAGE_URI="${2:-}"
      shift 2
      ;;
    --expected-irsa-role-arn)
      EXPECTED_IRSA_ROLE_ARN="${2:-}"
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
  if [[ -z "${file_path}" || ! -s "${file_path}" ]]; then
    echo "Missing required ${label}: ${file_path}" >&2
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

kubectl_cmd() {
  if [[ -n "${KUBE_CONTEXT}" ]]; then
    kubectl --context "${KUBE_CONTEXT}" "$@"
  else
    kubectl "$@"
  fi
}

case "${CLUSTER_CHECK}" in
  true|false) ;;
  *)
    echo "--cluster-check must be true or false." >&2
    exit 1
    ;;
esac

if [[ -z "${PACKAGE_DIR}" ]]; then
  echo "--package-dir is required." >&2
  usage >&2
  exit 1
fi

require_command grep
require_command sha256sum
require_command date

SECRET_MANIFEST="${PACKAGE_DIR}/backend-runtime-secret.yaml"
RUNTIME_MANIFEST="${PACKAGE_DIR}/aws-runtime-manifest.yaml"
PREFLIGHT_REPORT="${PACKAGE_DIR}/preflight-report.txt"
APPLY_ORDER="${PACKAGE_DIR}/apply-order.txt"
PACKAGE_README="${PACKAGE_DIR}/README.txt"

require_file "${SECRET_MANIFEST}" "backend runtime Secret manifest"
require_file "${RUNTIME_MANIFEST}" "AWS runtime manifest"
require_file "${PREFLIGHT_REPORT}" "preflight report"
require_file "${APPLY_ORDER}" "manual apply order"
require_file "${PACKAGE_README}" "deployment package README"

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}/deployment-package"

# Package integrity and boundary checks.
assert_contains '^kind: Secret$' "${SECRET_MANIFEST}" "Secret manifest must contain a Kubernetes Secret."
assert_contains '^type: Opaque$' "${SECRET_MANIFEST}" "Secret manifest must explicitly be Opaque."
assert_contains 'name: terraformers-backend-runtime-secrets' "${SECRET_MANIFEST}" "Secret manifest must use the backend runtime Secret name."

assert_not_contains '<[^>]+>|registry\.example\.com/terraformers-backend|public\.ecr\.aws/example|replace-with-immutable-tag' "${RUNTIME_MANIFEST}" "Runtime manifest must not contain placeholder values."
assert_not_contains '^kind: Ingress$|type: LoadBalancer' "${RUNTIME_MANIFEST}" "Runtime manifest must not expose public ingress or LoadBalancer service in the first rollout."
assert_contains '^kind: Deployment$' "${RUNTIME_MANIFEST}" "Runtime manifest must contain a Deployment."
assert_contains '^kind: ServiceAccount$' "${RUNTIME_MANIFEST}" "Runtime manifest must contain a ServiceAccount."
assert_contains '^kind: Service$' "${RUNTIME_MANIFEST}" "Runtime manifest must contain a Service."
assert_contains 'SPRING_PROFILES_ACTIVE: prod' "${RUNTIME_MANIFEST}" "Runtime manifest must run with prod profile."
assert_contains 'terraformers-backend-runtime-secrets' "${RUNTIME_MANIFEST}" "Runtime manifest must reference the backend runtime Secret."
assert_contains 'eks\.amazonaws\.com/role-arn:' "${RUNTIME_MANIFEST}" "Runtime manifest must include an IRSA annotation."

if grep -E -q 'image: .+:latest([[:space:]]*)?$' "${RUNTIME_MANIFEST}"; then
  echo "Runtime manifest must not use a latest image tag." >&2
  exit 1
fi

if [[ -n "${EXPECTED_IMAGE_URI}" ]]; then
  if ! grep -F -q "image: ${EXPECTED_IMAGE_URI}" "${RUNTIME_MANIFEST}"; then
    echo "Runtime manifest does not contain expected image URI: ${EXPECTED_IMAGE_URI}" >&2
    exit 1
  fi
fi

if [[ -n "${EXPECTED_IRSA_ROLE_ARN}" ]]; then
  if ! grep -F -q "eks.amazonaws.com/role-arn: ${EXPECTED_IRSA_ROLE_ARN}" "${RUNTIME_MANIFEST}"; then
    echo "Runtime manifest does not contain expected IRSA role ARN: ${EXPECTED_IRSA_ROLE_ARN}" >&2
    exit 1
  fi
fi

assert_contains '\[aws-runtime-preflight\] verification completed' "${PREFLIGHT_REPORT}" "Preflight report must show successful verification."
assert_contains 'kubectl .*apply -f' "${APPLY_ORDER}" "Apply order must contain manual kubectl apply commands."
assert_contains 'aws-runtime-rollout-smoke.sh' "${APPLY_ORDER}" "Apply order must include rollout smoke command."
assert_not_contains 'terraform apply|terraform destroy' "${APPLY_ORDER}" "Apply order must not contain Terraform apply or destroy commands."

{
  sha256sum "${SECRET_MANIFEST}" | sed "s#${SECRET_MANIFEST}#backend-runtime-secret.yaml#"
  sha256sum "${RUNTIME_MANIFEST}" | sed "s#${RUNTIME_MANIFEST}#aws-runtime-manifest.yaml#"
  sha256sum "${PREFLIGHT_REPORT}" | sed "s#${PREFLIGHT_REPORT}#preflight-report.txt#"
  sha256sum "${APPLY_ORDER}" | sed "s#${APPLY_ORDER}#apply-order.txt#"
} > "${OUTPUT_DIR}/deployment-package/package-sha256.txt"

cp "${PREFLIGHT_REPORT}" "${OUTPUT_DIR}/deployment-package/preflight-report.txt"
cp "${APPLY_ORDER}" "${OUTPUT_DIR}/deployment-package/apply-order.txt"
cp "${PACKAGE_README}" "${OUTPUT_DIR}/deployment-package/README.txt"

cat > "${OUTPUT_DIR}/rollout-readiness-checklist.txt" <<EOF
AWS runtime live rollout readiness checklist

Manual checks before running apply-order.txt:
[ ] Confirm KUBE_CONTEXT points to the intended EKS cluster.
[ ] Confirm namespace is ${NAMESPACE}.
[ ] Review backend-runtime-secret.yaml locally; do not copy it into shared evidence.
[ ] Review aws-runtime-manifest.yaml image URI, IRSA role ARN, namespace, Service type, and SecretRef.
[ ] Confirm preflight-report.txt ends with [aws-runtime-preflight] verification completed.
[ ] Confirm no public ingress or LoadBalancer service is introduced.
[ ] Confirm optional adapters remain disabled for the first rollout.
[ ] Confirm rollback path: delete or roll back the backend Deployment/Service/ServiceAccount and Secret if smoke fails.
[ ] After manual apply, run scripts/deploy/aws-runtime-rollout-smoke.sh.
[ ] After smoke succeeds, run scripts/deploy/collect-aws-runtime-evidence.sh.
EOF

if [[ "${CLUSTER_CHECK}" == "true" ]]; then
  require_command kubectl
  {
    echo "[aws-runtime-readiness] kube context"
    kubectl_cmd config current-context
    echo "[aws-runtime-readiness] kubectl client"
    kubectl_cmd version --client=true
    echo "[aws-runtime-readiness] namespace"
    kubectl_cmd get namespace "${NAMESPACE}"
    echo "[aws-runtime-readiness] auth checks"
    kubectl_cmd auth can-i get deployments -n "${NAMESPACE}"
    kubectl_cmd auth can-i create deployments -n "${NAMESPACE}"
    kubectl_cmd auth can-i patch deployments -n "${NAMESPACE}"
    kubectl_cmd auth can-i get services -n "${NAMESPACE}"
    kubectl_cmd auth can-i create services -n "${NAMESPACE}"
    kubectl_cmd auth can-i patch services -n "${NAMESPACE}"
    kubectl_cmd auth can-i get serviceaccounts -n "${NAMESPACE}"
    kubectl_cmd auth can-i create serviceaccounts -n "${NAMESPACE}"
    kubectl_cmd auth can-i patch serviceaccounts -n "${NAMESPACE}"
    kubectl_cmd auth can-i get secrets -n "${NAMESPACE}"
    kubectl_cmd auth can-i create secrets -n "${NAMESPACE}"
    kubectl_cmd auth can-i patch secrets -n "${NAMESPACE}"
  } > "${OUTPUT_DIR}/cluster-readiness.txt"
else
  echo "[aws-runtime-readiness] cluster checks skipped" > "${OUTPUT_DIR}/cluster-readiness.txt"
fi

cat > "${OUTPUT_DIR}/readiness-report.txt" <<EOF
AWS runtime live rollout readiness report

generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
namespace=${NAMESPACE}
package_dir=${PACKAGE_DIR}
cluster_check=${CLUSTER_CHECK}
manual_apply_boundary=required
terraform_apply_executed=false
kubectl_apply_executed=false
public_ingress_allowed=false
adapter_enablement_allowed=false
status=ready-for-manual-apply

Files:
- deployment-package/package-sha256.txt
- deployment-package/preflight-report.txt
- deployment-package/apply-order.txt
- deployment-package/README.txt
- rollout-readiness-checklist.txt
- cluster-readiness.txt

Private manifest handling:
- backend-runtime-secret.yaml is hashed but not copied into this readiness artifact.
EOF

echo "[aws-runtime-readiness] verification completed"
echo "Generated AWS runtime live rollout readiness report: ${OUTPUT_DIR}"
