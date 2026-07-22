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
    --output <path>

Renders a Kubernetes Secret manifest from a private .env file using kubectl
client-side generation. This script does not contact AWS and does not apply
the Secret to a cluster. The output path is required to avoid printing secret
material to standard output.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --secret-name) SECRET_NAME="${2:-}"; shift 2 ;;
    --output) OUTPUT_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "${ENV_FILE}" ]]; then
  echo "--env-file is required." >&2
  usage >&2
  exit 1
fi
if [[ -z "${OUTPUT_FILE}" ]]; then
  echo "--output is required so Secret material is not printed to standard output." >&2
  usage >&2
  exit 1
fi
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Environment file not found: ${ENV_FILE}" >&2
  exit 1
fi

for command_name in kubectl awk grep sort uniq; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
done

required_keys=(
  SPRING_DATASOURCE_URL
  SPRING_DATASOURCE_USERNAME
  SPRING_DATASOURCE_PASSWORD
  COGNITO_REGION
  COGNITO_USER_POOL_ID
  COGNITO_USER_POOL_CLIENT_ID
  COGNITO_JWKS_URL
  S3_BUCKET_NAME
)
optional_keys=(
  ANALYSIS_RESULT_BUCKET_NAME
  BEDROCK_MODEL_ID
  BEDROCK_EMBEDDING_MODEL_ID
  OPENSEARCH_ENDPOINT
  INDEX_NAME
  VECTOR_FIELD_NAME
  CONTENT_FIELD_NAME
  AI_LOG_QUEUE_URL
  TERRAFORM_LOG_QUEUE_URL
)

allowed_key_file="$(mktemp)"
active_key_file="$(mktemp)"
trap 'rm -f "${allowed_key_file}" "${active_key_file}"' EXIT
printf '%s\n' "${required_keys[@]}" "${optional_keys[@]}" | sort -u >"${allowed_key_file}"

malformed_lines="$(awk '
  /^[[:space:]]*$/ { next }
  /^[[:space:]]*#/ { next }
  /^[A-Z][A-Z0-9_]*=.*/ { next }
  { print NR }
' "${ENV_FILE}")"
if [[ -n "${malformed_lines}" ]]; then
  echo "Malformed lines in ${ENV_FILE}: ${malformed_lines//$'\n'/, }" >&2
  exit 1
fi

awk -F= '
  /^[[:space:]]*$/ { next }
  /^[[:space:]]*#/ { next }
  /^[A-Z][A-Z0-9_]*=/ { print $1 }
' "${ENV_FILE}" >"${active_key_file}"

duplicate_keys="$(sort "${active_key_file}" | uniq -d)"
if [[ -n "${duplicate_keys}" ]]; then
  echo "Duplicate keys in ${ENV_FILE}: ${duplicate_keys//$'\n'/, }" >&2
  exit 1
fi
unknown_keys="$(grep -Fvx -f "${allowed_key_file}" "${active_key_file}" || true)"
if [[ -n "${unknown_keys}" ]]; then
  echo "Unknown backend runtime Secret keys in ${ENV_FILE}: ${unknown_keys//$'\n'/, }" >&2
  exit 1
fi

get_env_value() {
  local key="$1"
  local line
  line="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 || true)"
  [[ -n "${line}" ]] || return 1
  printf '%s' "${line#*=}"
}

validate_value() {
  local key="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    echo "Empty value is not allowed for ${key}." >&2
    exit 1
  fi
  if [[ "${value}" == *"<"* || "${value}" == *">"* ]]; then
    echo "Angle-bracket placeholder value is not allowed for ${key}." >&2
    exit 1
  fi
  if [[ "${value,,}" == *"adapter-disabled"* || "${value,,}" == *"disabled.example"* ]]; then
    echo "Disabled-adapter placeholder value is not allowed for ${key}." >&2
    exit 1
  fi
}

for key in "${required_keys[@]}"; do
  value="$(get_env_value "${key}" || true)"
  if [[ -z "${value}" ]]; then
    echo "Missing required key in ${ENV_FILE}: ${key}" >&2
    exit 1
  fi
  validate_value "${key}" "${value}"
done

active_optional_count=0
for key in "${optional_keys[@]}"; do
  if grep -qE "^${key}=" "${ENV_FILE}"; then
    value="$(get_env_value "${key}")"
    validate_value "${key}" "${value}"
    active_optional_count=$((active_optional_count + 1))
  fi
done

rendered_manifest="$(kubectl \
  -n "${NAMESPACE}" \
  create secret generic "${SECRET_NAME}" \
  --from-env-file="${ENV_FILE}" \
  --dry-run=client \
  -o yaml)"

if ! grep -Eq '^type:' <<<"${rendered_manifest}"; then
  rendered_manifest="$(printf '%s\n' "${rendered_manifest}" | awk '
    { print }
    /^kind: Secret$/ { print "type: Opaque" }
  ')"
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"
umask 077
printf '%s\n' "${rendered_manifest}" >"${OUTPUT_FILE}"
chmod 600 "${OUTPUT_FILE}"

echo "Rendered private Secret manifest: ${OUTPUT_FILE}"
echo "Validated base runtime keys: ${#required_keys[@]}"
echo "Active optional runtime keys: ${active_optional_count}"
