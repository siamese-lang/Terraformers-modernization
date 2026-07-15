#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${REPO_ROOT}/artifacts/aws-runtime-input-bundle"
FIXTURE_DIR="${ARTIFACT_DIR}/fixtures"
BUNDLE_DIR="${ARTIFACT_DIR}/bundle"
BAD_OUTPUT="${ARTIFACT_DIR}/missing-password-output.txt"
LATEST_OUTPUT="${ARTIFACT_DIR}/latest-image-output.txt"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
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
    echo "Unexpected pattern: ${pattern}" >&2
    exit 1
  fi
}

require_command python3
require_command grep

rm -rf "${ARTIFACT_DIR}"
mkdir -p "${FIXTURE_DIR}" "${BUNDLE_DIR}"

cat > "${FIXTURE_DIR}/runtime.json" <<'JSON'
{
  "backend_image_repository_url": {"value": "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend"},
  "upload_bucket_name": {"value": "terraformers-dev-uploads"},
  "result_bucket_name": {"value": "terraformers-dev-results"},
  "ai_log_queue_url": {"value": "https://sqs.ap-northeast-2.amazonaws.com/123456789012/terraformers-dev-ai-log"},
  "terraform_log_queue_url": {"value": "https://sqs.ap-northeast-2.amazonaws.com/123456789012/terraformers-dev-terraform-log"},
  "backend_runtime_secret_arn": {"value": "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:terraformers/dev/backend/runtime"}
}
JSON

cat > "${FIXTURE_DIR}/stateful.json" <<'JSON'
{
  "spring_datasource_url": {"value": "jdbc:mariadb://terraformers-dev-db.example.internal:3306/terraformers"},
  "database_username": {"value": "terraformers_app"},
  "cognito_region": {"value": "ap-northeast-2"},
  "cognito_user_pool_id": {"value": "ap-northeast-2_ExamplePool"},
  "cognito_user_pool_client_id": {"value": "exampleclientid"},
  "cognito_jwks_url": {"value": "https://cognito-idp.ap-northeast-2.amazonaws.com/ap-northeast-2_ExamplePool/.well-known/jwks.json"}
}
JSON

cat > "${FIXTURE_DIR}/eks.json" <<'JSON'
{
  "backend_namespace": {"value": "terraformers-runtime"},
  "backend_irsa_role_arn": {"value": "arn:aws:iam::123456789012:role/terraformers-dev-backend-irsa"}
}
JSON

python3 "${REPO_ROOT}/scripts/deploy/build-aws-runtime-input-bundle.py" \
  --runtime-outputs-json "${FIXTURE_DIR}/runtime.json" \
  --stateful-outputs-json "${FIXTURE_DIR}/stateful.json" \
  --eks-outputs-json "${FIXTURE_DIR}/eks.json" \
  --database-password "example-private-password" \
  --image-uri "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend:sha-test123" \
  --output-dir "${BUNDLE_DIR}"

SECRET_ENV="${BUNDLE_DIR}/backend-runtime-secret.env"
MANIFEST_ENV="${BUNDLE_DIR}/aws-runtime-manifest.env"
APPLY_ORDER="${BUNDLE_DIR}/apply-order.txt"

for generated_file in "${SECRET_ENV}" "${MANIFEST_ENV}" "${APPLY_ORDER}"; do
  if [[ ! -s "${generated_file}" ]]; then
    echo "Generated file is missing or empty: ${generated_file}" >&2
    exit 1
  fi
done

assert_contains '^SPRING_DATASOURCE_URL=jdbc:mariadb://terraformers-dev-db\.example\.internal:3306/terraformers$' "${SECRET_ENV}" "Secret env must include datasource URL."
assert_contains '^SPRING_DATASOURCE_USERNAME=terraformers_app$' "${SECRET_ENV}" "Secret env must include datasource username."
assert_contains '^SPRING_DATASOURCE_PASSWORD=example-private-password$' "${SECRET_ENV}" "Secret env must include supplied database password."
assert_contains '^COGNITO_USER_POOL_ID=ap-northeast-2_ExamplePool$' "${SECRET_ENV}" "Secret env must include Cognito user pool ID."
assert_contains '^S3_BUCKET_NAME=terraformers-dev-uploads$' "${SECRET_ENV}" "Secret env must include upload bucket."
assert_contains '^AI_LOG_QUEUE_URL=https://sqs\.ap-northeast-2\.amazonaws\.com/123456789012/terraformers-dev-ai-log$' "${SECRET_ENV}" "Secret env must include AI queue URL."
assert_contains '^OPENSEARCH_ENDPOINT=https://opensearch-disabled\.example\.internal$' "${SECRET_ENV}" "Secret env must include disabled OpenSearch default."
assert_contains '^BACKEND_IMAGE_URI=123456789012\.dkr\.ecr\.ap-northeast-2\.amazonaws\.com/terraformers-backend:sha-test123$' "${MANIFEST_ENV}" "Manifest env must include image URI."
assert_contains '^BACKEND_IRSA_ROLE_ARN=arn:aws:iam::123456789012:role/terraformers-dev-backend-irsa$' "${MANIFEST_ENV}" "Manifest env must include IRSA role ARN."
assert_contains '^KUBERNETES_NAMESPACE=terraformers-runtime$' "${MANIFEST_ENV}" "Manifest env must include namespace."
assert_contains 'render-backend-runtime-secret\.sh' "${APPLY_ORDER}" "Apply order must include Secret render command."
assert_contains 'render-aws-runtime-manifest\.sh' "${APPLY_ORDER}" "Apply order must include manifest render command."
assert_not_contains '<|>' "${SECRET_ENV}" "Secret env must not contain angle bracket placeholders."
assert_not_contains '<|>' "${MANIFEST_ENV}" "Manifest env must not contain angle bracket placeholders."

set +e
python3 "${REPO_ROOT}/scripts/deploy/build-aws-runtime-input-bundle.py" \
  --runtime-outputs-json "${FIXTURE_DIR}/runtime.json" \
  --stateful-outputs-json "${FIXTURE_DIR}/stateful.json" \
  --eks-outputs-json "${FIXTURE_DIR}/eks.json" \
  --image-uri "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend:sha-test123" \
  --output-dir "${ARTIFACT_DIR}/missing-password-bundle" \
  >"${BAD_OUTPUT}" 2>&1
missing_status=$?
set -e

if [[ ${missing_status} -eq 0 ]]; then
  echo "Bundle builder must fail when database password is missing." >&2
  exit 1
fi
assert_contains 'SPRING_DATASOURCE_PASSWORD is required' "${BAD_OUTPUT}" "Missing database password failure must be explicit."

set +e
python3 "${REPO_ROOT}/scripts/deploy/build-aws-runtime-input-bundle.py" \
  --runtime-outputs-json "${FIXTURE_DIR}/runtime.json" \
  --stateful-outputs-json "${FIXTURE_DIR}/stateful.json" \
  --eks-outputs-json "${FIXTURE_DIR}/eks.json" \
  --database-password "example-private-password" \
  --image-uri "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend:latest" \
  --output-dir "${ARTIFACT_DIR}/latest-image-bundle" \
  >"${LATEST_OUTPUT}" 2>&1
latest_status=$?
set -e

if [[ ${latest_status} -eq 0 ]]; then
  echo "Bundle builder must reject latest image tag by default." >&2
  exit 1
fi
assert_contains 'must not use latest' "${LATEST_OUTPUT}" "Latest image rejection must be explicit."

echo "[aws-runtime-input-bundle] verification completed"
