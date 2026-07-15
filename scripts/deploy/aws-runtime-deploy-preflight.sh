#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/deploy/aws-runtime-deploy-preflight.sh \
    --runtime-manifest /path/to/aws-runtime-manifest.yaml \
    --secret-manifest /path/to/backend-runtime-secret.yaml \
    [--namespace terraformers-runtime] \
    [--context kube-context] \
    [--server-dry-run true|false]

Purpose:
  Validate that the rendered AWS runtime manifest and runtime Secret manifest are ready
  to be applied to an existing Kubernetes cluster. This script does not apply resources.

Checks:
  - kubectl is available
  - manifest files exist and do not contain obvious placeholders
  - current or provided kube context can reach the cluster
  - namespace exists
  - caller has basic permissions for Secret, ServiceAccount, Deployment, and Service
  - rendered manifest contains backend Deployment, ServiceAccount, prod profile, SecretRef, and IRSA annotation
  - client-side dry-run succeeds
  - optional server-side dry-run succeeds
USAGE
}

NAMESPACE="terraformers-runtime"
KUBE_CONTEXT=""
RUNTIME_MANIFEST=""
SECRET_MANIFEST=""
SERVER_DRY_RUN="true"

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
    --runtime-manifest)
      RUNTIME_MANIFEST="$2"
      shift 2
      ;;
    --secret-manifest)
      SECRET_MANIFEST="$2"
      shift 2
      ;;
    --server-dry-run)
      SERVER_DRY_RUN="$2"
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
  if [[ -z "${file_path}" ]]; then
    echo "Missing required ${label} path." >&2
    usage >&2
    exit 1
  fi
  if [[ ! -f "${file_path}" ]]; then
    echo "${label} file not found: ${file_path}" >&2
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

require_permission() {
  local verb="$1"
  local resource="$2"
  if ! kubectl_cmd auth can-i "${verb}" "${resource}" -n "${NAMESPACE}" >/dev/null; then
    echo "kubectl auth check failed for ${verb} ${resource} in namespace ${NAMESPACE}." >&2
    exit 1
  fi
}

case "${SERVER_DRY_RUN}" in
  true|false) ;;
  *)
    echo "--server-dry-run must be true or false." >&2
    exit 1
    ;;
esac

require_command kubectl
require_command grep
require_file "${RUNTIME_MANIFEST}" "runtime manifest"
require_file "${SECRET_MANIFEST}" "Secret manifest"

assert_not_contains '<[^>]+>' "${RUNTIME_MANIFEST}" "Runtime manifest must not contain angle-bracket placeholders."
assert_not_contains '<[^>]+>' "${SECRET_MANIFEST}" "Secret manifest must not contain angle-bracket placeholders."
assert_not_contains 'replace-with-immutable-tag|registry\.example\.com|public\.ecr\.aws/example' "${RUNTIME_MANIFEST}" "Runtime manifest must not contain public-safe placeholder image values."

assert_contains '^kind: Deployment$' "${RUNTIME_MANIFEST}" "Runtime manifest must contain a Deployment."
assert_contains '^kind: ServiceAccount$' "${RUNTIME_MANIFEST}" "Runtime manifest must contain a ServiceAccount."
assert_contains '^kind: Service$' "${RUNTIME_MANIFEST}" "Runtime manifest must contain a Service."
assert_contains 'SPRING_PROFILES_ACTIVE: prod' "${RUNTIME_MANIFEST}" "Runtime manifest must run with prod profile."
assert_contains 'terraformers-backend-runtime-secrets' "${RUNTIME_MANIFEST}" "Runtime manifest must reference backend runtime Secret."
assert_contains 'eks\.amazonaws\.com/role-arn:' "${RUNTIME_MANIFEST}" "Runtime manifest must include backend IRSA annotation."
assert_contains '^kind: Secret$' "${SECRET_MANIFEST}" "Secret manifest must contain a Secret."
assert_contains 'name: terraformers-backend-runtime-secrets' "${SECRET_MANIFEST}" "Secret manifest must create terraformers-backend-runtime-secrets."

printf '[aws-runtime-preflight] kube context: '
kubectl_cmd config current-context

kubectl_cmd version --client >/dev/null
kubectl_cmd get namespace "${NAMESPACE}" >/dev/null

require_permission get pods
require_permission get deployments
require_permission get services
require_permission get serviceaccounts
require_permission get secrets
require_permission create secrets
require_permission patch secrets
require_permission create deployments
require_permission patch deployments
require_permission create services
require_permission patch services
require_permission create serviceaccounts
require_permission patch serviceaccounts

echo "[aws-runtime-preflight] client-side dry-run"
kubectl_cmd apply --dry-run=client -n "${NAMESPACE}" -f "${SECRET_MANIFEST}" >/dev/null
kubectl_cmd apply --dry-run=client -n "${NAMESPACE}" -f "${RUNTIME_MANIFEST}" >/dev/null

if [[ "${SERVER_DRY_RUN}" == "true" ]]; then
  echo "[aws-runtime-preflight] server-side dry-run"
  kubectl_cmd apply --dry-run=server -n "${NAMESPACE}" -f "${SECRET_MANIFEST}" >/dev/null
  kubectl_cmd apply --dry-run=server -n "${NAMESPACE}" -f "${RUNTIME_MANIFEST}" >/dev/null
fi

echo "[aws-runtime-preflight] verification completed"
