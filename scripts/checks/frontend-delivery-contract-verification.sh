#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/infra/terraform/envs/frontend-delivery"
MAIN_TF="${TERRAFORM_DIR}/main.tf"
OUTPUTS_TF="${TERRAFORM_DIR}/outputs.tf"
FRONTEND_API="${REPO_ROOT}/frontend/src/utils/api.js"
FRONTEND_ENV="${REPO_ROOT}/frontend/.env.example"
FRONTEND_WORKFLOW="${REPO_ROOT}/.github/workflows/frontend-delivery.yml"
EVIDENCE_DIR="${REPO_ROOT}/artifacts/frontend-delivery-contract"
FIXTURE_DIR="${EVIDENCE_DIR}/fixtures"
BUNDLE_DIR="${EVIDENCE_DIR}/input-bundle"
SUMMARY="${EVIDENCE_DIR}/verification-summary.txt"

assert_contains() {
  local pattern="$1" file="$2" message="$3"
  if ! grep -E -q -- "${pattern}" "${file}"; then
    echo "${message}" >&2
    echo "Expected pattern: ${pattern}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local pattern="$1" file="$2" message="$3"
  if grep -E -q -- "${pattern}" "${file}"; then
    echo "${message}" >&2
    echo "Matched pattern: ${pattern}" >&2
    exit 1
  fi
}

for command_name in grep python3; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Required command not found: ${command_name}" >&2
    exit 1
  }
done

for required_file in \
  "${MAIN_TF}" \
  "${OUTPUTS_TF}" \
  "${FRONTEND_API}" \
  "${FRONTEND_ENV}" \
  "${FRONTEND_WORKFLOW}"; do
  test -s "${required_file}" || {
    echo "Expected non-empty file: ${required_file}" >&2
    exit 1
  }
done

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${FIXTURE_DIR}"

assert_contains 'resource "aws_s3_bucket" "frontend"' "${MAIN_TF}" "Missing frontend S3 bucket."
assert_contains 'object_ownership = "BucketOwnerEnforced"' "${MAIN_TF}" "Frontend bucket must enforce owner-only object ownership."
for setting in block_public_acls block_public_policy ignore_public_acls restrict_public_buckets; do
  assert_contains "${setting}[[:space:]]*=[[:space:]]*true" "${MAIN_TF}" "Frontend bucket must keep ${setting}=true."
done
assert_contains 'status = "Enabled"' "${MAIN_TF}" "Frontend bucket versioning must remain enabled."
assert_contains 'noncurrent_version_expiration' "${MAIN_TF}" "Frontend rollback retention is missing."

assert_contains 'resource "aws_cloudfront_origin_access_control" "frontend"' "${MAIN_TF}" "CloudFront OAC is required."
assert_contains 'signing_behavior[[:space:]]*=[[:space:]]*"always"' "${MAIN_TF}" "OAC must sign every origin request."
assert_contains 'signing_protocol[[:space:]]*=[[:space:]]*"sigv4"' "${MAIN_TF}" "OAC must use SigV4."
assert_not_contains 'resource "aws_cloudfront_origin_access_identity"' "${MAIN_TF}" "Legacy OAI must not return."
assert_not_contains 'aws_s3_bucket_website_configuration' "${MAIN_TF}" "Public S3 website hosting must not return."

assert_contains 'path_pattern[[:space:]]*=[[:space:]]*"/api/\*"' "${MAIN_TF}" "CloudFront must route /api/*."
assert_contains 'name = "Managed-CachingDisabled"' "${MAIN_TF}" "API caching must be disabled."
assert_contains 'name = "Managed-AllViewerExceptHostHeader"' "${MAIN_TF}" "API viewer context forwarding is missing."
assert_contains "uri.indexOf\('/api/'\) === 0" "${MAIN_TF}" "SPA rewrite must exclude API routes."
assert_not_contains 'custom_error_response' "${MAIN_TF}" "Global SPA error substitution must not replace API errors."
assert_not_contains '/actuator/\*' "${MAIN_TF}" "Actuator must not be a public CloudFront behavior."
assert_contains 'identifiers = \["cloudfront.amazonaws.com"\]' "${MAIN_TF}" "Bucket policy must trust the CloudFront service principal."
assert_contains 'variable = "AWS:SourceArn"' "${MAIN_TF}" "Bucket policy must restrict the distribution SourceArn."

for output_name in frontend_bucket_name cloudfront_distribution_id cloudfront_distribution_domain_name frontend_base_url frontend_api_base_url; do
  assert_contains "output \"${output_name}\"" "${OUTPUTS_TF}" "Missing frontend output: ${output_name}."
done

assert_contains "const API_BASE_URL = envApiBaseUrl \|\| '';" "${FRONTEND_API}" "React must support relative same-origin API paths."
assert_contains 'Production requests will use relative paths' "${FRONTEND_API}" "Production same-origin fallback is not explicit."
assert_not_contains 'Set the deployed backend origin when the frontend is served as a static production bundle' "${FRONTEND_ENV}" "Frontend guidance must not require cross-origin delivery."

assert_contains 'deploy_frontend:' "${FRONTEND_WORKFLOW}" "Frontend workflow needs an explicit deployment switch."
assert_contains 'default: false' "${FRONTEND_WORKFLOW}" "Frontend delivery must default to build-only."
assert_contains 'aws-actions/configure-aws-credentials@v4' "${FRONTEND_WORKFLOW}" "Frontend delivery must use GitHub OIDC."
assert_contains 'role-to-assume:.*AWS_ROLE_TO_ASSUME' "${FRONTEND_WORKFLOW}" "Frontend delivery must require an OIDC role."
assert_not_contains 'secrets\.AWS_ACCESS_KEY_ID|secrets\.AWS_SECRET_ACCESS_KEY' "${FRONTEND_WORKFLOW}" "Long-lived AWS keys are forbidden."
assert_contains "--cache-control 'no-cache,no-store,must-revalidate'" "${FRONTEND_WORKFLOW}" "Mutable frontend files need no-cache metadata."
assert_contains "--cache-control 'public,max-age=31536000,immutable'" "${FRONTEND_WORKFLOW}" "Hashed assets need immutable caching."
assert_contains 'aws cloudfront wait invalidation-completed' "${FRONTEND_WORKFLOW}" "Delivery must wait for invalidation completion."
assert_not_contains "--paths '/\*'" "${FRONTEND_WORKFLOW}" "Do not invalidate immutable assets globally."
assert_contains "--paths '/' '/index.html' '/asset-manifest.json' '/manifest.json'" "${FRONTEND_WORKFLOW}" "Only mutable entrypoints should be invalidated."

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
assert_not_contains 'PASSWORD|SECRET|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY' "${BUILD_ENV}" "Frontend build bundle must contain public values only."
assert_contains '"api_base_mode": "same-origin-relative"' "${SOURCE_MAP}" "Source map must record same-origin API mode."
assert_contains '^frontend_build_variable_count=4$' "${BUNDLE_SUMMARY}" "Frontend build variable count must remain four."
assert_contains 'aws s3 sync frontend/build s3://terraformers-dev-frontend-fixture --delete' "${APPLY_ORDER}" "Manual delivery order must include S3 sync."
assert_contains 'aws cloudfront create-invalidation --distribution-id E123456789FIXTURE' "${APPLY_ORDER}" "Manual delivery order must include invalidation."

printf '%s\n' \
  'frontend_delivery_contract=passed' \
  'frontend_delivery_input_bundle=generated' \
  'frontend_delivery_workflow=guarded-oidc' \
  'frontend_build_variable_count=4' \
  'frontend_bucket_access=private' \
  'frontend_bucket_versioning=enabled' \
  'cloudfront_origin_access=OAC-sigv4' \
  'api_routing=same-origin-/api/*' \
  'api_cache=disabled' \
  'spa_rewrite=cloudfront-function' \
  'api_error_substitution=disabled' \
  'actuator_public_route=absent' \
  'mutable_cache_control=no-cache' \
  'static_cache_control=immutable-one-year' \
  'invalidation_scope=mutable-entrypoints-only' \
  'frontend_output_groups=resolved' \
  'cluster_contact=none' \
  'aws_mutation=none' \
  >"${SUMMARY}"
cat "${SUMMARY}"
