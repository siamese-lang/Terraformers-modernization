#!/usr/bin/env bash
set -euo pipefail

SECRET_NAME="terraformers-backend-runtime-secrets"
NAMESPACE="terraformers-runtime"
ENV_FILE=""
OUTPUT_FILE=""

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy/render-backend-runtime-secret.sh \
    --env-file <path> \
    [--namespace terraformers-runtime] \
    [--secret-name terraformers-backend-runtime-secrets] \
    [--output <path>]

Renders a Kubernetes Secret manifest from a local .env file using kubectl client-side dry-run.
This script does not apply the Secret to a cluster.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --namespace)
      NAMESPACE="${2:-}"
      shift 2
      ;;
    --secret-name)
      SECRET_NAME="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
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

if [[ -z "${ENV_FILE}" ]]; then
  echo "--env-file is required." >&2
  usage >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Environment file not found: ${ENV_FILE}" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Required command not found: kubectl" >&2
  exit 1
fi

required_keys=(
  SPRING_DATASOURCE_URL
  SPRING_DATASOURCE_USERNAME
  SPRING_DATASOURCE_PASSWORD
  COGNITO_REGION
  COGNITO_USER_POOL_ID
  COGNITO_USER_POOL_CLIENT_ID
  COGNITO_JWKS_URL
  S3_BUCKET_NAME
  ANALYSIS_RESULT_BUCKET_NAME
  AI_LOG_QUEUE_URL
  TERRAFORM_LOG_QUEUE_URL
  BEDROCK_MODEL_ID
  BEDROCK_EMBEDDING_MODEL_ID
  OPENSEARCH_ENDPOINT
  INDEX_NAME
  VECTOR_FIELD_NAME
  CONTENT_FIELD_NAME
)

get_env_value() {
  local key="$1"
  local line
  line="$(grep -E "^[[:space:]]*${key}=" "${ENV_FILE}" | tail -n 1 || true)"
  if [[ -z "${line}" ]]; then
    return 1
  fi
  printf '%s' "${line#*=}"
}

for key in "${required_keys[@]}"; do
  value="$(get_env_value "${key}" || true)"
  if [[ -z "${value}" ]]; then
    echo "Missing required key in ${ENV_FILE}: ${key}" >&2
    exit 1
  fi
  if [[ "${value}" =~ ^\<.*\>$ ]]; then
    echo "Placeholder value is not allowed for ${key}." >&2
    exit 1
  fi
done

rendered_manifest="$(kubectl \
  -n "${NAMESPACE}" \
  create secret generic "${SECRET_NAME}" \
  --from-env-file="${ENV_FILE}" \
  --dry-run=client \
  -o yaml)"

if [[ -n "${OUTPUT_FILE}" ]]; then
  mkdir -p "$(dirname "${OUTPUT_FILE}")"
  printf '%s\n' "${rendered_manifest}" > "${OUTPUT_FILE}"
  echo "Rendered Secret manifest: ${OUTPUT_FILE}"
else
  printf '%s\n' "${rendered_manifest}"
fi
