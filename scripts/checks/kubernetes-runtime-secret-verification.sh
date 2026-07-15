#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_EXAMPLE="${REPO_ROOT}/infra/kubernetes/runtime-secret.env.example"
RENDER_SCRIPT="${REPO_ROOT}/scripts/deploy/render-backend-runtime-secret.sh"
RENDERED_SECRET="$(mktemp)"
INVALID_ENV="$(mktemp)"

cleanup() {
  rm -f "${RENDERED_SECRET}" "${INVALID_ENV}"
}
trap cleanup EXIT

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

require_command kubectl
require_command bash
require_command grep

chmod +x "${RENDER_SCRIPT}"

echo "[kubernetes-secret] rendering runtime Secret from example env"
"${RENDER_SCRIPT}" \
  --env-file "${ENV_EXAMPLE}" \
  --namespace terraformers-runtime \
  --output "${RENDERED_SECRET}"

assert_contains '^kind: Secret$' "${RENDERED_SECRET}" "Rendered manifest must be a Kubernetes Secret."
assert_contains 'name: terraformers-backend-runtime-secrets' "${RENDERED_SECRET}" "Rendered Secret must use the backend runtime Secret name."
assert_contains 'namespace: terraformers-runtime' "${RENDERED_SECRET}" "Rendered Secret must target terraformers-runtime namespace."
assert_contains '^type: Opaque$' "${RENDERED_SECRET}" "Rendered Secret must be Opaque."
assert_contains 'SPRING_DATASOURCE_URL:' "${RENDERED_SECRET}" "Rendered Secret must include datasource URL."
assert_contains 'COGNITO_JWKS_URL:' "${RENDERED_SECRET}" "Rendered Secret must include Cognito JWKS URL."
assert_contains 'AI_LOG_QUEUE_URL:' "${RENDERED_SECRET}" "Rendered Secret must include AI log queue URL."
assert_contains 'CONTENT_FIELD_NAME:' "${RENDERED_SECRET}" "Rendered Secret must include OpenSearch content field name."

assert_not_contains '<[^>]+>' "${ENV_EXAMPLE}" "Runtime Secret env example must not contain angle-bracket placeholders."
assert_not_contains '[0-9]{12}' "${ENV_EXAMPLE}" "Runtime Secret env example must not contain 12-digit account-like identifiers."

cp "${ENV_EXAMPLE}" "${INVALID_ENV}"
sed -i '/^SPRING_DATASOURCE_PASSWORD=/d' "${INVALID_ENV}"

echo "[kubernetes-secret] verifying missing required key is rejected"
if "${RENDER_SCRIPT}" --env-file "${INVALID_ENV}" >/dev/null 2>&1; then
  echo "render script must reject env files missing required keys" >&2
  exit 1
fi

echo "[kubernetes-secret] verification completed"
