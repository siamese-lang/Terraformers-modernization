#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/infra/terraform/envs/frontend-delivery"
MAIN_TF="${TERRAFORM_DIR}/main.tf"
OUTPUTS_TF="${TERRAFORM_DIR}/outputs.tf"
VARIABLES_TF="${TERRAFORM_DIR}/variables.tf"
FRONTEND_API="${REPO_ROOT}/frontend/src/utils/api.js"
FRONTEND_ENV="${REPO_ROOT}/frontend/.env.example"
EVIDENCE_DIR="${REPO_ROOT}/artifacts/frontend-delivery-contract"
FIXTURE_DIR="${EVIDENCE_DIR}/fixtures"
BUNDLE_DIR="${EVIDENCE_DIR}/input-bundle"
SUMMARY="${EVIDENCE_DIR}/verification-summary.txt"

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

for command_name in grep python3; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
done

for required_file in "${MAIN_TF}" "${OUTPUTS_TF}" "${VARIABLES_TF}" "${FRONTEND_API}" "${FRONTEND_ENV}"; do
  if [[ ! -s "${required_file}" ]]; then
    echo "Expected non-empty file: ${required_file}" >&2
    exit 1
  fi
done

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${FIXTURE_DIR}"

assert_contains 'resource "aws_s3_bucket" "frontend"' "${MAIN_TF}" "Frontend delivery must provision a dedicated S3 bucket."
assert_contains 'object_ownership = "BucketOwnerEnforced"' "${MAIN_TF}" "Frontend bucket must disable ACL ownership ambiguity."
for setting in block_public_acls block_public_policy ignore_public_acls restrict_public_buckets; do
  assert_contains "${setting}[[:space:]]*=[[:space:]]*true" "${MAIN_TF}" "Frontend bucket public access block must keep ${setting}=true."
done
assert_contains 'status = "Enabled"' "${MAIN_TF}" "Frontend bucket versioning must remain enabled for rollback."
assert_contains 'noncurrent_version_expiration' "${MAIN_TF}" "Frontend bucket must retain noncurrent deployment versions."

assert_contains 'resource "aws_cloudfront_origin_access_control" "frontend"' "${MAIN_TF}" "CloudFront must use OAC for private S3 access."
assert_contains 'signing_behavior[[:space:]]*=[[:space:]]*"always"' "${MAIN_TF}" "OAC must sign every S3 origin request."
assert_contains 'signing_protocol[[:space:]]*=[[:space:]]*"sigv4"' "${MAIN_TF}" "OAC must use SigV4."
assert_not_contains 'resource "aws_cloudfront_origin_access_identity"' "${MAIN_TF}" "Legacy CloudFront OAI must not be reintroduced."
assert_not_contains 'aws_s3_bucket_website_configuration' "${MAIN_TF}" "Private frontend delivery must not use the public S3 website endpoint."

assert_contains 'path_pattern[[:space:]]*=[[:space:]]*"/api/\*"' "${MAIN_TF}" "CloudFront must route /api/* to the backend origin."
assert_contains 'name = "Managed-CachingDisabled"' "${MAIN_TF}" "Backend API responses must use the managed caching-disabled policy."
assert_contains 'name = "Managed-AllViewerExceptHostHeader"' "${MAIN_TF}" "Backend origin must receive viewer auth/query/cookie context without the CloudFront Host header."
assert_contains "uri.indexOf\('/api/'\) === 0" "${MAIN_TF}" "SPA rewrite must explicitly exclude backend API routes."
assert_not_contains 'custom_error_response' "${MAIN_TF}" "Distribution-wide error substitution would turn backend API errors into index.html."
assert_not_contains '/actuator/\*' "${MAIN_TF}" "CloudFront must not expose an actuator cache behavior."

assert_contains 'identifiers = \["cloudfront.amazonaws.com"\]' "${MAIN_TF}" "Frontend bucket policy must trust only the CloudFront service principal."
assert_contains 'variable = "AWS:SourceArn"' "${MAIN_TF}" "Frontend bucket policy must be scoped to the distribution ARN."
assert_contains 'values[[:space:]]*=[[:space:]]*\[aws_cloudfront_distribution.frontend.arn\]' "${MAIN_TF}" "Frontend bucket policy source must be the exact distribution ARN."

for output_name in frontend_bucket_name cloudfront_distribution_id cloudfront_distribution_domain_name frontend_base_url frontend_api_base_url; do
  assert_contains "output \"${output_name}\"" "${OUTPUTS_TF}" "Missing frontend delivery output: ${output_name}."
done

assert_contains "const API_BASE_URL = envApiBaseUrl \|\| '';" "${FRONTEND_API}" "React client must support relative same-origin API paths."
assert_contains 'Production requests will use relative paths' "${FRONTEND_API}" "Production same-origin fallback must remain explicit."
assert_not_contains 'Set the deployed backend origin when the frontend is served as a static production bundle' "${FRONTEND_ENV}" "Frontend environment guidance must not require a cross-origin backend URL."

cat >"${FIXTURE_DIR}/stateful.json" <<'JSON'
{
  "cognito_region": {"value": "ap-northeast-2"},
  "cognito_user_pool_id": {"value": "ap-northeast-2_fixture"},
  "cognito_user_pool_client_id": {"value": "fixture-client-id"}
}
JSON

cat >"${FIXTURE_DIR}/frontend.json" <<'JSON'
{
  "frontend_bucket_name": {"value": "terraformers-dev-frontend-fixture"},
  "cloudfront_distribution_id": {"value": "E123456789FIXTURE"},
  "cloudfront_distribution_domain_name": {"value": "d111111abcdef8.cloudfront.net"}
}
JSON

python3 "${REPO_ROOT}/scripts/deploy/build-frontend-delivery-input-bundle.py" \
  --stateful-outputs-json "${FIXTURE_DIR}/stateful.json" \
  --frontend-outputs-json "${FIXTURE_DIR}/frontend.json" \
  --output-dir "${BUNDLE_DIR}"

BUILD_ENV="${BUNDLE_DIR}/frontend-build.env"
SOURCE_MAP="${BUNDLE_DIR}/delivery-source-map.json"
BUNDLE_SUMMARY="${BUNDLE_DIR}/bundle-summary.txt"
APPLY_ORDER="${BUNDLE_DIR}/apply-order.txt"

for generated_file in "${BUILD_ENV}" "${SOURCE_MAP}" "${BUNDLE_SUMMARY}" "${APPLY_ORDER}"; do
  test -s "${generated_file}"
done

grep -qx 'REACT_APP_API_BASE_URL=' "${BUILD_ENV}"
grep -qx 'REACT_APP_AWS_REGION=ap-northeast-2' "${BUILD_ENV}"
grep -qx 'REACT_APP_COGNITO_USER_POOL_ID=ap-northeast-2_fixture' "${BUILD_ENV}"
grep -qx 'REACT_APP_COGNITO_USER_POOL_CLIENT_ID=fixture-client-id' "${BUILD_ENV}"
assert_not_contains 'PASSWORD|SECRET|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY' "${BUILD_ENV}" "Frontend build bundle must contain browser-public values only."
assert_contains '"api_base_mode": "same-origin-relative"' "${SOURCE_MAP}" "Frontend source map must record same-origin API mode."
assert_contains '^frontend_build_variable_count=4$' "${BUNDLE_SUMMARY}" "Frontend build variable count must remain four."
assert_contains 'aws s3 sync frontend/build s3://terraformers-dev-frontend-fixture --delete' "${APPLY_ORDER}" "Manual delivery order must include convergent S3 sync."
assert_contains 'aws cloudfront create-invalidation --distribution-id E123456789FIXTURE' "${APPLY_ORDER}" "Manual delivery order must include CloudFront invalidation."

printf '%s\n' \
  'frontend_delivery_contract=passed' \
  'frontend_delivery_input_bundle=generated' \
  'frontend_build_variable_count=4' \
  'frontend_bucket_access=private' \
  'frontend_bucket_versioning=enabled' \
  'cloudfront_origin_access=OAC-sigv4' \
  'api_routing=same-origin-/api/*' \
  'api_cache=disabled' \
  'spa_rewrite=cloudfront-function' \
  'api_error_substitution=disabled' \
  'actuator_public_route=absent' \
  'frontend_output_groups=resolved' \
  'cluster_contact=none' \
  'aws_mutation=none' \
  >"${SUMMARY}"

cat "${SUMMARY}"
