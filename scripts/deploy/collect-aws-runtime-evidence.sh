#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/deploy/collect-aws-runtime-evidence.sh \
    [--namespace terraformers-runtime] \
    [--context kube-context] \
    [--output-dir artifacts/aws-runtime-evidence] \
    [--package-dir /tmp/terraformers-deployment-package] \
    [--smoke-dir artifacts/aws-runtime-rollout-smoke] \
    [--image-uri registry.example.com/terraformers-backend:tag] \
    [--irsa-role-arn arn:aws:iam::123456789012:role/terraformers-backend] \
    [--cluster-check true|false]

Purpose:
  Collect post-manual-apply AWS runtime evidence into a reviewable directory.
  This script never runs terraform apply, kubectl apply, public ingress changes, or adapter enablement.

Evidence:
  - metadata.txt
  - evidence-checklist.txt
  - deployment package hashes and preflight report, when --package-dir is provided
  - rollout smoke outputs, when --smoke-dir exists
  - Kubernetes deployment, pod, service, endpoint, event, and log snapshots when --cluster-check=true
USAGE
}

NAMESPACE="terraformers-runtime"
KUBE_CONTEXT=""
OUTPUT_DIR="artifacts/aws-runtime-evidence"
PACKAGE_DIR=""
SMOKE_DIR="artifacts/aws-runtime-rollout-smoke"
IMAGE_URI="${BACKEND_IMAGE_URI:-}"
IRSA_ROLE_ARN="${BACKEND_IRSA_ROLE_ARN:-}"
DEPLOYMENT_NAME="terraformers-backend"
SERVICE_NAME="terraformers-backend"
CLUSTER_CHECK="true"
LOG_TAIL="200"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACE="${2:-}"
      shift 2
      ;;
    --context)
      KUBE_CONTEXT="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --package-dir)
      PACKAGE_DIR="${2:-}"
      shift 2
      ;;
    --smoke-dir)
      SMOKE_DIR="${2:-}"
      shift 2
      ;;
    --image-uri)
      IMAGE_URI="${2:-}"
      shift 2
      ;;
    --irsa-role-arn)
      IRSA_ROLE_ARN="${2:-}"
      shift 2
      ;;
    --deployment-name)
      DEPLOYMENT_NAME="${2:-}"
      shift 2
      ;;
    --service-name)
      SERVICE_NAME="${2:-}"
      shift 2
      ;;
    --cluster-check)
      CLUSTER_CHECK="${2:-}"
      shift 2
      ;;
    --log-tail)
      LOG_TAIL="${2:-}"
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

case "${CLUSTER_CHECK}" in
  true|false) ;;
  *)
    echo "--cluster-check must be true or false." >&2
    exit 1
    ;;
esac

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

sha256_file() {
  local file_path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file_path}"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file_path}"
  else
    echo "Required command not found: sha256sum or shasum" >&2
    exit 1
  fi
}

copy_if_exists() {
  local source_path="$1"
  local target_dir="$2"
  if [[ -f "${source_path}" ]]; then
    mkdir -p "${target_dir}"
    cp "${source_path}" "${target_dir}/"
  fi
}

run_kubectl_capture() {
  local output_file="$1"
  shift
  mkdir -p "$(dirname "${output_file}")"
  printf '$ kubectl' > "${output_file}"
  if [[ -n "${KUBE_CONTEXT}" ]]; then
    printf ' --context %s' "${KUBE_CONTEXT}" >> "${output_file}"
  fi
  printf ' %q' "$@" >> "${output_file}"
  printf '\n\n' >> "${output_file}"

  set +e
  kubectl_cmd "$@" >> "${output_file}" 2>&1
  local status=$?
  set -e
  printf '\n--- exit_code=%s\n' "${status}" >> "${output_file}"
}

require_command date
require_command cp
require_command mkdir

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

cat > "${OUTPUT_DIR}/metadata.txt" <<EOF
collected_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
namespace=${NAMESPACE}
kube_context=${KUBE_CONTEXT:-current-context}
deployment_name=${DEPLOYMENT_NAME}
service_name=${SERVICE_NAME}
cluster_check=${CLUSTER_CHECK}
backend_image_uri=${IMAGE_URI:-not-provided}
backend_irsa_role_arn=${IRSA_ROLE_ARN:-not-provided}
package_dir=${PACKAGE_DIR:-not-provided}
smoke_dir=${SMOKE_DIR:-not-provided}
EOF

cat > "${OUTPUT_DIR}/evidence-checklist.txt" <<'EOF'
AWS runtime evidence checklist

Pre-apply package evidence:
- deployment-package/manifest-sha256.txt
- deployment-package/preflight-report.txt
- deployment-package/apply-order.txt

Post-apply Kubernetes evidence:
- kubernetes/context.txt
- kubernetes/namespace.yaml
- kubernetes/deployment.yaml
- kubernetes/deployment-describe.txt
- kubernetes/replicasets.txt
- kubernetes/pods-wide.txt
- kubernetes/pods.yaml
- kubernetes/service.yaml
- kubernetes/serviceaccount.yaml
- kubernetes/endpoints.yaml
- kubernetes/events.txt
- kubernetes/backend-logs.txt

Rollout smoke evidence:
- smoke/rollout-status.txt
- smoke/pods.txt
- smoke/endpoints.yaml
- smoke/health.json
- smoke/upload-response.json
- smoke/project-tree.json
- smoke/main-tf-response.json

Boundaries:
- No terraform apply
- No kubectl apply
- No public ingress or ALB exposure
- No adapter enablement
EOF

PACKAGE_EVIDENCE_DIR="${OUTPUT_DIR}/deployment-package"
mkdir -p "${PACKAGE_EVIDENCE_DIR}"
if [[ -n "${PACKAGE_DIR}" && -d "${PACKAGE_DIR}" ]]; then
  : > "${PACKAGE_EVIDENCE_DIR}/manifest-sha256.txt"
  for manifest_name in backend-runtime-secret.yaml aws-runtime-manifest.yaml; do
    if [[ -f "${PACKAGE_DIR}/${manifest_name}" ]]; then
      sha256_file "${PACKAGE_DIR}/${manifest_name}" >> "${PACKAGE_EVIDENCE_DIR}/manifest-sha256.txt"
    fi
  done
  copy_if_exists "${PACKAGE_DIR}/preflight-report.txt" "${PACKAGE_EVIDENCE_DIR}"
  copy_if_exists "${PACKAGE_DIR}/apply-order.txt" "${PACKAGE_EVIDENCE_DIR}"
  copy_if_exists "${PACKAGE_DIR}/README.txt" "${PACKAGE_EVIDENCE_DIR}"
else
  echo "package_dir was not provided or does not exist; package evidence skipped." > "${PACKAGE_EVIDENCE_DIR}/README.txt"
fi

SMOKE_EVIDENCE_DIR="${OUTPUT_DIR}/smoke"
mkdir -p "${SMOKE_EVIDENCE_DIR}"
if [[ -n "${SMOKE_DIR}" && -d "${SMOKE_DIR}" ]]; then
  for smoke_file in \
    rollout-status.txt \
    pods.txt \
    endpoints.yaml \
    port-forward.log \
    health.json \
    upload-response.json \
    project-tree.json \
    main-tf-response.json; do
    copy_if_exists "${SMOKE_DIR}/${smoke_file}" "${SMOKE_EVIDENCE_DIR}"
  done
else
  echo "smoke_dir was not provided or does not exist; rollout smoke evidence skipped." > "${SMOKE_EVIDENCE_DIR}/README.txt"
fi

KUBERNETES_EVIDENCE_DIR="${OUTPUT_DIR}/kubernetes"
mkdir -p "${KUBERNETES_EVIDENCE_DIR}"
if [[ "${CLUSTER_CHECK}" == "true" ]]; then
  require_command kubectl
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/context.txt" config current-context
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/namespace.yaml" get namespace "${NAMESPACE}" -o yaml
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/deployment.yaml" -n "${NAMESPACE}" get deployment "${DEPLOYMENT_NAME}" -o yaml
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/deployment-describe.txt" -n "${NAMESPACE}" describe deployment "${DEPLOYMENT_NAME}"
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/replicasets.txt" -n "${NAMESPACE}" get replicasets -l app.kubernetes.io/name=terraformers-backend -o wide
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/pods-wide.txt" -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=terraformers-backend -o wide
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/pods.yaml" -n "${NAMESPACE}" get pods -l app.kubernetes.io/name=terraformers-backend -o yaml
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/service.yaml" -n "${NAMESPACE}" get service "${SERVICE_NAME}" -o yaml
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/serviceaccount.yaml" -n "${NAMESPACE}" get serviceaccount terraformers-backend -o yaml
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/endpoints.yaml" -n "${NAMESPACE}" get endpoints "${SERVICE_NAME}" -o yaml
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/events.txt" -n "${NAMESPACE}" get events --sort-by=.lastTimestamp
  run_kubectl_capture "${KUBERNETES_EVIDENCE_DIR}/backend-logs.txt" -n "${NAMESPACE}" logs "deployment/${DEPLOYMENT_NAME}" --all-containers=true --tail="${LOG_TAIL}"
else
  echo "kubectl collection skipped because --cluster-check=false." > "${KUBERNETES_EVIDENCE_DIR}/README.txt"
fi

echo "Generated AWS runtime evidence: ${OUTPUT_DIR}"
