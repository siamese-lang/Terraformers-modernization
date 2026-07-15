#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_DIR="${REPO_ROOT}/infra/kubernetes/overlays/aws-runtime-template"
DEFAULT_NAMESPACE="terraformers-runtime"

IMAGE_URI="${BACKEND_IMAGE_URI:-}"
IRSA_ROLE_ARN="${BACKEND_IRSA_ROLE_ARN:-}"
NAMESPACE="${KUBERNETES_NAMESPACE:-${DEFAULT_NAMESPACE}}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
WORK_DIR=""

usage() {
  cat <<'USAGE'
Usage:
  render-aws-runtime-manifest.sh \
    --image-uri <immutable-backend-image-uri> \
    --irsa-role-arn <backend-irsa-role-arn> \
    [--namespace terraformers-runtime] \
    [--output /path/to/rendered.yaml]

Environment variable equivalents:
  BACKEND_IMAGE_URI
  BACKEND_IRSA_ROLE_ARN
  KUBERNETES_NAMESPACE
  OUTPUT_FILE

The script renders the AWS runtime Kubernetes overlay only. It does not run kubectl apply.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image-uri)
      IMAGE_URI="${2:-}"
      shift 2
      ;;
    --irsa-role-arn)
      IRSA_ROLE_ARN="${2:-}"
      shift 2
      ;;
    --namespace)
      NAMESPACE="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --help|-h)
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

require_non_empty() {
  local name="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    echo "${name} is required." >&2
    usage >&2
    exit 1
  fi
}

reject_angle_placeholder() {
  local name="$1"
  local value="$2"
  if [[ "${value}" == *"<"* || "${value}" == *">"* ]]; then
    echo "${name} must not contain angle-bracket placeholders." >&2
    exit 1
  fi
}

require_command kubectl
require_command python3
require_non_empty "BACKEND_IMAGE_URI" "${IMAGE_URI}"
require_non_empty "BACKEND_IRSA_ROLE_ARN" "${IRSA_ROLE_ARN}"
require_non_empty "KUBERNETES_NAMESPACE" "${NAMESPACE}"
reject_angle_placeholder "BACKEND_IMAGE_URI" "${IMAGE_URI}"
reject_angle_placeholder "BACKEND_IRSA_ROLE_ARN" "${IRSA_ROLE_ARN}"
reject_angle_placeholder "KUBERNETES_NAMESPACE" "${NAMESPACE}"

if [[ "${IMAGE_URI}" != *":"* ]]; then
  echo "BACKEND_IMAGE_URI must include an immutable tag." >&2
  exit 1
fi

IMAGE_TAG="${IMAGE_URI##*:}"
IMAGE_REPOSITORY="${IMAGE_URI%:*}"

if [[ -z "${IMAGE_REPOSITORY}" || -z "${IMAGE_TAG}" || "${IMAGE_REPOSITORY}" == "${IMAGE_URI}" ]]; then
  echo "BACKEND_IMAGE_URI must be in repository:tag form." >&2
  exit 1
fi

if [[ "${IMAGE_TAG}" == "latest" && "${ALLOW_LATEST_IMAGE_TAG:-false}" != "true" ]]; then
  echo "BACKEND_IMAGE_URI must not use the latest tag unless ALLOW_LATEST_IMAGE_TAG=true." >&2
  exit 1
fi

if [[ "${IRSA_ROLE_ARN}" != arn:aws:iam::*:role/* ]]; then
  echo "BACKEND_IRSA_ROLE_ARN must look like an IAM role ARN." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
cleanup() {
  if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
    rm -rf "${WORK_DIR}"
  fi
}
trap cleanup EXIT

cp -R "${TEMPLATE_DIR}" "${WORK_DIR}/aws-runtime"
OVERLAY_DIR="${WORK_DIR}/aws-runtime"

python3 - "${OVERLAY_DIR}/kustomization.yaml" "${IMAGE_REPOSITORY}" "${IMAGE_TAG}" "${NAMESPACE}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
image_repository = sys.argv[2]
image_tag = sys.argv[3]
namespace = sys.argv[4]
text = path.read_text()
text = text.replace("namespace: terraformers-runtime", f"namespace: {namespace}")
text = text.replace("newName: registry.example.com/terraformers-backend", f"newName: {image_repository}")
text = text.replace("newTag: immutable-tag", f"newTag: {image_tag}")
needle = "  - path: backend-deployment-patch.yaml\n"
replacement = needle + "  - path: backend-serviceaccount-irsa-patch.yaml\n"
if "backend-serviceaccount-irsa-patch.yaml" not in text:
    text = text.replace(needle, replacement)
path.write_text(text)
PY

cat > "${OVERLAY_DIR}/backend-serviceaccount-irsa-patch.yaml" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: terraformers-backend
  annotations:
    eks.amazonaws.com/role-arn: ${IRSA_ROLE_ARN}
EOF

if [[ -z "${OUTPUT_FILE}" ]]; then
  kubectl kustomize "${OVERLAY_DIR}"
else
  mkdir -p "$(dirname "${OUTPUT_FILE}")"
  kubectl kustomize "${OVERLAY_DIR}" > "${OUTPUT_FILE}"
  echo "Rendered AWS runtime manifest: ${OUTPUT_FILE}"
fi
