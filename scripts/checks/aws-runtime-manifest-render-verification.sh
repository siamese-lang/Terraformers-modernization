#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RENDER_SCRIPT="${REPO_ROOT}/scripts/deploy/render-aws-runtime-manifest.sh"
ARTIFACT_DIR="${REPO_ROOT}/artifacts/aws-runtime-manifest-render"
RENDERED_MANIFEST="${ARTIFACT_DIR}/aws-runtime-rendered.yaml"
MISSING_OUTPUT="${ARTIFACT_DIR}/missing-image-output.txt"

SAMPLE_IMAGE_URI="registry.example.com/terraformers-backend:sha-test1234"
SAMPLE_IRSA_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/terraformers-dev-backend-irsa"
SAMPLE_NAMESPACE="terraformers-runtime"

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
  if ! grep -F -q "${pattern}" "${file}"; then
    echo "${message}" >&2
    echo "Expected text: ${pattern}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if grep -F -q "${pattern}" "${file}"; then
    echo "${message}" >&2
    echo "Unexpected text: ${pattern}" >&2
    exit 1
  fi
}

require_command kubectl
require_command python3
require_command grep

rm -rf "${ARTIFACT_DIR}"
mkdir -p "${ARTIFACT_DIR}"

bash "${RENDER_SCRIPT}" \
  --image-uri "${SAMPLE_IMAGE_URI}" \
  --irsa-role-arn "${SAMPLE_IRSA_ROLE_ARN}" \
  --namespace "${SAMPLE_NAMESPACE}" \
  --output "${RENDERED_MANIFEST}"

assert_contains "namespace: ${SAMPLE_NAMESPACE}" "${RENDERED_MANIFEST}" "Rendered manifest must use the requested namespace."
assert_contains "image: ${SAMPLE_IMAGE_URI}" "${RENDERED_MANIFEST}" "Rendered manifest must use the requested backend image URI."
assert_contains "eks.amazonaws.com/role-arn: ${SAMPLE_IRSA_ROLE_ARN}" "${RENDERED_MANIFEST}" "Rendered manifest must include the requested IRSA role annotation."
assert_contains "name: terraformers-backend-runtime-secrets" "${RENDERED_MANIFEST}" "Rendered manifest must keep runtime Secret dependency."
assert_contains "SPRING_PROFILES_ACTIVE: prod" "${RENDERED_MANIFEST}" "Rendered manifest must keep prod profile."
assert_contains 'S3_READER_ENABLED: "true"' "${RENDERED_MANIFEST}" "AWS runtime must enable the private S3 reader."
assert_contains 'BEDROCK_PROVIDER_ENABLED: "true"' "${RENDERED_MANIFEST}" "AWS runtime must enable the Bedrock analysis provider."
assert_contains 'RETRIEVAL_MODE: REQUIRED' "${RENDERED_MANIFEST}" "AWS runtime must require reference retrieval."
assert_contains 'BEDROCK_EMBEDDING_MODEL_ID: amazon.titan-embed-text-v2:0' "${RENDERED_MANIFEST}" "AWS runtime must use the corpus embedding model."
assert_contains 'INDEX_NAME: terraformers-reference-v1' "${RENDERED_MANIFEST}" "AWS runtime must reuse the existing reference index."
assert_contains 'CORPUS_VERSION: terraformers-reference-v2' "${RENDERED_MANIFEST}" "AWS runtime must filter retrieval to corpus v2."
assert_contains 'PROVIDER_VERSION: 5.100.0' "${RENDERED_MANIFEST}" "AWS runtime must filter retrieval to the pinned provider version."
assert_contains 'OPENSEARCH_TOP_K: "8"' "${RENDERED_MANIFEST}" "AWS runtime must retrieve a bounded multi-resource reference set."
assert_contains 'VECTOR_FIELD_NAME: embedding' "${RENDERED_MANIFEST}" "AWS runtime must use the configured vector field."
assert_contains 'CONTENT_FIELD_NAME: content' "${RENDERED_MANIFEST}" "AWS runtime must use the configured content field."
assert_contains 'EXPECTED_VECTOR_DIMENSION: "1024"' "${RENDERED_MANIFEST}" "AWS runtime must validate the embedding dimension."
assert_not_contains 'BEDROCK_EMBEDDING_ENABLED' "${RENDERED_MANIFEST}" "Removed embedding switch must not remain in the manifest."
assert_not_contains 'OPENSEARCH_RETRIEVER_ENABLED' "${RENDERED_MANIFEST}" "Removed retriever switch must not remain in the manifest."
assert_not_contains "public.ecr.aws/example/terraformers-backend" "${RENDERED_MANIFEST}" "Rendered manifest must not keep base placeholder image."
assert_not_contains "registry.example.com/terraformers-backend:immutable-tag" "${RENDERED_MANIFEST}" "Rendered manifest must not keep template image placeholder."
assert_not_contains "replace-with-immutable-tag" "${RENDERED_MANIFEST}" "Rendered manifest must not keep immutable tag placeholder."
assert_not_contains "<" "${RENDERED_MANIFEST}" "Rendered manifest must not contain angle-bracket placeholders."
assert_not_contains ">" "${RENDERED_MANIFEST}" "Rendered manifest must not contain angle-bracket placeholders."

set +e
bash "${RENDER_SCRIPT}" \
  --irsa-role-arn "${SAMPLE_IRSA_ROLE_ARN}" \
  --namespace "${SAMPLE_NAMESPACE}" \
  --output "${ARTIFACT_DIR}/should-not-render.yaml" \
  >"${MISSING_OUTPUT}" 2>&1
missing_status=$?
set -e

if [[ ${missing_status} -eq 0 ]]; then
  echo "Render script must fail when image URI is missing." >&2
  exit 1
fi

assert_contains "BACKEND_IMAGE_URI is required" "${MISSING_OUTPUT}" "Missing image URI failure must be explicit."

echo "[aws-runtime-manifest-render] verification completed"
