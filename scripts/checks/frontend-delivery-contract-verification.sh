#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/infra/terraform/envs/frontend-delivery"
MAIN_TF="${TERRAFORM_DIR}/main.tf"
OUTPUTS_TF="${TERRAFORM_DIR}/outputs.tf"
VARIABLES_TF="${TERRAFORM_DIR}/variables.tf"
VERSIONS_TF="${TERRAFORM_DIR}/versions.tf"
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
  "${VARIABLES_TF}" \
  "${VERSIONS_TF}" \
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
assert_contains 'signing_behavior[[:space:]]*=[[:space:]]*"always"' "${MAIN_TF}" "OAC must sign every S3 origin request."
assert_contains 'signing_protocol[[:space:]]*=[[:space:]]*"sigv4"' "${MAIN_TF}" "OAC must use SigV4."
assert_not_contains 'resource "aws_cloudfront_origin_access_identity"' "${MAIN_TF}" "Legacy OAI must not return."
assert_not_contains 'aws_s3_bucket_website_configuration' "${MAIN_TF}" "Public S3 website hosting must not return."

assert_contains 'resource "aws_cloudfront_vpc_origin" "backend"' "${MAIN_TF}" "Backend API must use a CloudFront VPC origin."
assert_contains 'data "aws_lb" "backend_origin"' "${MAIN_TF}" "Backend origin must resolve an approved ALB ARN."
assert_contains 'data.aws_lb.backend_origin.internal' "${MAIN_TF}" "Terraform must reject internet-facing ALBs."
assert_contains 'load_balancer_type == "application"' "${MAIN_TF}" "Terraform must reject non-ALB origins."
assert_contains 'vpc_origin_config' "${MAIN_TF}" "CloudFront distribution must reference the private VPC origin."
assert_contains 'origin_protocol_policy[[:space:]]*=[[:space:]]*"http-only"' "${MAIN_TF}" "Private CloudFront-to-ALB origin protocol must match the internal HTTP listener."
assert_not_contains 'custom_origin_config' "${MAIN_TF}" "Public custom-origin routing must not return."
assert_contains 'version[[:space:]]*=[[:space:]]*"~> 6\.0"' "${VERSIONS_TF}" "AWS provider v6 is required for VPC origin support."

assert_contains 'path_pattern[[:space:]]*=[[:space:]]*"/api/\*"' "${MAIN_TF}" "CloudFront must route /api/*."
assert_contains 'name = "Managed-CachingDisabled"' "${MAIN_TF}" "API caching must be disabled."
assert_contains 'name = "Managed-AllViewerExceptHostHeader"' "${MAIN_TF}" "API viewer context forwarding is missing."
assert_contains "uri.indexOf\('/api/'\) === 0" "${MAIN_TF}" "SPA rewrite must exclude API routes."
assert_not_contains 'custom_error_response' "${MAIN_TF}" "Global SPA error substitution must not replace API errors."
assert_not_contains '/actuator/\*' "${MAIN_TF}" "Actuator must not be a public CloudFront behavior."
assert_contains 'identifiers = \["cloudfront.amazonaws.com"\]' "${MAIN_TF}" "Bucket policy must trust the CloudFront service principal."
assert_contains 'variable = "AWS:SourceArn"' "${MAIN_TF}" "Bucket policy must restrict the distribution SourceArn."

assert_contains 'resource "aws_iam_role" "frontend_delivery"' "${MAIN_TF}" "Missing frontend delivery IAM role."
assert_contains 'var.github_oidc_provider_arn' "${MAIN_TF}" "Frontend role must reuse the existing GitHub OIDC provider ARN input."
assert_not_contains 'resource "aws_iam_openid_connect_provider"' "${MAIN_TF}" "Frontend delivery must not create a duplicate GitHub OIDC provider."
assert_contains '"token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"' "${MAIN_TF}" "Frontend delivery trust must restrict OIDC audience."
assert_contains '"token.actions.githubusercontent.com:sub" = local.frontend_delivery_github_subject' "${MAIN_TF}" "Frontend delivery trust must use the exact environment subject."
assert_contains 'repo:\${var.github_repository}:environment:\${var.github_environment}' "${MAIN_TF}" "Frontend delivery subject must be repository plus GitHub Environment."
assert_contains 'default[[:space:]]*=[[:space:]]*"siamese-lang/Terraformers-modernization"' "${VARIABLES_TF}" "GitHub repository default must be the current repo."
assert_contains 'default[[:space:]]*=[[:space:]]*"frontend-delivery"' "${VARIABLES_TF}" "GitHub environment default must be frontend-delivery."
assert_contains 'github_oidc_provider_arn must identify the existing token.actions.githubusercontent.com provider' "${VARIABLES_TF}" "Provider ARN validation must require GitHub Actions OIDC."
assert_contains 's3:ListBucket' "${MAIN_TF}" "Frontend role must list only the frontend bucket."
assert_contains 's3:PutObject' "${MAIN_TF}" "Frontend role must upload frontend bundle objects."
assert_contains 's3:DeleteObject' "${MAIN_TF}" "Frontend role must allow sync --delete for frontend bundle objects."
assert_contains 's3:AbortMultipartUpload' "${MAIN_TF}" "Frontend role must include minimum multipart cleanup permission."
assert_contains 'Resource = aws_s3_bucket.frontend.arn' "${MAIN_TF}" "Bucket-level permissions must target only the frontend bucket ARN."
assert_contains 'Resource = "\${aws_s3_bucket.frontend.arn}/\*"' "${MAIN_TF}" "Object permissions must target only frontend bucket objects."
assert_contains 'cloudfront:CreateInvalidation' "${MAIN_TF}" "Frontend role must create CloudFront invalidations."
assert_contains 'cloudfront:GetInvalidation' "${MAIN_TF}" "Frontend role must read invalidation status."
assert_contains 'Resource = aws_cloudfront_distribution.frontend.arn' "${MAIN_TF}" "CloudFront permissions must target only the frontend distribution ARN."
assert_not_contains 'secretsmanager:|iam:|eks:|rds:|sqs:' "${MAIN_TF}" "Frontend delivery role must not grant unrelated service permissions."

for output_name in \
  frontend_bucket_name \
  cloudfront_distribution_id \
  cloudfront_distribution_domain_name \
  frontend_base_url \
  frontend_api_base_url \
  backend_vpc_origin_id \
  backend_origin_load_balancer_arn \
  backend_origin_load_balancer_dns_name \
  frontend_delivery_role_arn \
  frontend_delivery_role_name \
  github_environment_name; do
  assert_contains "output \"${output_name}\"" "${OUTPUTS_TF}" "Missing frontend output: ${output_name}."
done

assert_contains "const API_BASE_URL = envApiBaseUrl \|\| '';" "${FRONTEND_API}" "React must support relative same-origin API paths."
assert_contains 'Production requests will use relative paths' "${FRONTEND_API}" "Production same-origin fallback is not explicit."
assert_not_contains 'Set the deployed backend origin when the frontend is served as a static production bundle' "${FRONTEND_ENV}" "Frontend guidance must not require cross-origin delivery."

assert_contains 'deploy_frontend:' "${FRONTEND_WORKFLOW}" "Frontend workflow needs an explicit deployment switch."
assert_contains 'default: false' "${FRONTEND_WORKFLOW}" "Frontend delivery must default to build-only."
assert_contains 'aws-actions/configure-aws-credentials@v4' "${FRONTEND_WORKFLOW}" "Frontend delivery must use GitHub OIDC."
assert_contains 'environment: frontend-delivery' "${FRONTEND_WORKFLOW}" "Frontend job must use the frontend-delivery GitHub Environment."
assert_contains 'FRONTEND_AWS_ROLE_TO_ASSUME:.*vars.FRONTEND_AWS_ROLE_TO_ASSUME' "${FRONTEND_WORKFLOW}" "Frontend workflow must use the canonical OIDC role variable."
assert_contains 'role-to-assume:.*FRONTEND_AWS_ROLE_TO_ASSUME' "${FRONTEND_WORKFLOW}" "Frontend delivery must require an OIDC role."
assert_not_contains 'aws_role_to_assume' "${FRONTEND_WORKFLOW}" "Arbitrary OIDC role workflow input must be removed."
assert_not_contains 'secrets\.AWS_ACCESS_KEY_ID|secrets\.AWS_SECRET_ACCESS_KEY|secrets\.AWS_ROLE_TO_ASSUME' "${FRONTEND_WORKFLOW}" "Long-lived AWS keys are forbidden."
assert_contains "--cache-control 'no-cache,no-store,must-revalidate'" "${FRONTEND_WORKFLOW}" "Mutable frontend files need no-cache metadata."
assert_contains "--cache-control 'public,max-age=31536000,immutable'" "${FRONTEND_WORKFLOW}" "Hashed assets need immutable caching."
assert_contains 'allowed-account-ids:.*EXPECTED_AWS_ACCOUNT_ID' "${FRONTEND_WORKFLOW}" "AWS credential configuration must restrict allowed account IDs."
assert_contains 'CALLER_ACCOUNT_ID=' "${FRONTEND_WORKFLOW}" "Workflow must verify the post-OIDC caller account."
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
  "cloudfront_distribution_domain_name": {"value": "d111111abcdef8.cloudfront.net"},
  "frontend_delivery_role_arn": {"value": "arn:aws:iam::123456789012:role/terraformers-dev-frontend-delivery"}
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
GITHUB_ENV_VARS="${BUNDLE_DIR}/github-environment-variables.env"
for generated_file in "${BUILD_ENV}" "${SOURCE_MAP}" "${BUNDLE_SUMMARY}" "${APPLY_ORDER}" "${GITHUB_ENV_VARS}"; do
  test -s "${generated_file}"
done

grep -qx 'REACT_APP_API_BASE_URL=' "${BUILD_ENV}"
grep -qx 'REACT_APP_AWS_REGION=ap-northeast-2' "${BUILD_ENV}"
grep -qx 'REACT_APP_COGNITO_USER_POOL_ID=ap-northeast-2_fixture' "${BUILD_ENV}"
grep -qx 'REACT_APP_COGNITO_USER_POOL_CLIENT_ID=fixture-client-id' "${BUILD_ENV}"
assert_not_contains 'PASSWORD|SECRET|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|JWT|Authorization' "${BUILD_ENV}" "Frontend build bundle must contain public values only."
grep -qx 'FRONTEND_AWS_ROLE_TO_ASSUME=arn:aws:iam::123456789012:role/terraformers-dev-frontend-delivery' "${GITHUB_ENV_VARS}"
grep -qx 'FRONTEND_BUCKET_NAME=terraformers-dev-frontend-fixture' "${GITHUB_ENV_VARS}"
grep -qx 'CLOUDFRONT_DISTRIBUTION_ID=E123456789FIXTURE' "${GITHUB_ENV_VARS}"
assert_not_contains 'PASSWORD|SECRET|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|JWT|Authorization' "${GITHUB_ENV_VARS}" "GitHub variable bundle must not contain secrets."
assert_contains '"frontend_delivery_role_arn": "arn:aws:iam::123456789012:role/terraformers-dev-frontend-delivery"' "${SOURCE_MAP}" "Source map must record the frontend delivery role ARN."
assert_contains '"api_base_mode": "same-origin-relative"' "${SOURCE_MAP}" "Source map must record same-origin API mode."
assert_contains '"invalidation_scope": "mutable-entrypoints-only"' "${SOURCE_MAP}" "Source map must record the limited invalidation scope."
assert_contains '^frontend_build_variable_count=4$' "${BUNDLE_SUMMARY}" "Frontend build variable count must remain four."
assert_contains '^invalidation_wait=required$' "${BUNDLE_SUMMARY}" "Bundle must require invalidation completion."
assert_contains 'aws s3 sync frontend/build s3://terraformers-dev-frontend-fixture' "${APPLY_ORDER}" "Manual delivery order must include mutable S3 sync."
assert_contains "--exclude 'static/\*'" "${APPLY_ORDER}" "Mutable sync must exclude immutable static assets."
assert_contains "--cache-control 'no-cache,no-store,must-revalidate'" "${APPLY_ORDER}" "Mutable sync must set no-cache metadata."
assert_contains 'aws s3 sync frontend/build/static s3://terraformers-dev-frontend-fixture/static' "${APPLY_ORDER}" "Manual delivery order must include static asset sync."
assert_contains "--cache-control 'public,max-age=31536000,immutable'" "${APPLY_ORDER}" "Static sync must set immutable metadata."
assert_contains 'aws cloudfront create-invalidation' "${APPLY_ORDER}" "Manual delivery order must include invalidation."
assert_contains '--distribution-id E123456789FIXTURE' "${APPLY_ORDER}" "Invalidation must target the Terraform output distribution."
assert_contains "--paths '/' '/index.html' '/asset-manifest.json' '/manifest.json'" "${APPLY_ORDER}" "Bundle must invalidate only mutable entrypoints."
assert_not_contains "--paths '/\*'" "${APPLY_ORDER}" "Bundle must not invalidate all immutable assets."
assert_contains 'aws cloudfront wait invalidation-completed' "${APPLY_ORDER}" "Bundle must wait for invalidation completion."

printf '%s\n' \
  'frontend_delivery_contract=passed' \
  'frontend_delivery_input_bundle=generated' \
  'frontend_delivery_workflow=guarded-oidc' \
  'frontend_delivery_role=terraform-managed' \
  'github_oidc_provider=reused-foundation-provider' \
  'github_oidc_subject=repo:siamese-lang/Terraformers-modernization:environment:frontend-delivery' \
  'frontend_build_variable_count=4' \
  'frontend_bucket_access=private' \
  'frontend_bucket_versioning=enabled' \
  'cloudfront_origin_access=OAC-sigv4' \
  'cloudfront_backend_origin=vpc-origin-internal-alb' \
  'public_custom_origin=absent' \
  'api_routing=same-origin-/api/*' \
  'api_cache=disabled' \
  'spa_rewrite=cloudfront-function' \
  'api_error_substitution=disabled' \
  'actuator_public_route=absent' \
  'mutable_cache_control=no-cache' \
  'static_cache_control=immutable-one-year' \
  'invalidation_scope=mutable-entrypoints-only' \
  'invalidation_wait=required' \
  'frontend_delivery_github_variables=generated' \
  'frontend_output_groups=resolved' \
  'cluster_contact=none' \
  'aws_mutation=none' \
  >"${SUMMARY}"
cat "${SUMMARY}"
