#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${REPO_ROOT}/artifacts/aws-runtime-deployment-package-verification"
FIXTURE_DIR="${ARTIFACT_DIR}/fixtures"
INPUT_BUNDLE_DIR="${ARTIFACT_DIR}/input-bundle"
PACKAGE_DIR="${ARTIFACT_DIR}/deployment-package"
MISSING_INPUT_OUTPUT="${ARTIFACT_DIR}/missing-input-output.txt"

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
    echo "Matched pattern: ${pattern}" >&2
    exit 1
  fi
}

require_file() {
  local file_path="$1"
  if [[ ! -s "${file_path}" ]]; then
    echo "Expected non-empty file: ${file_path}" >&2
    exit 1
  fi
}

require_command bash
require_command grep
require_command kubectl
require_command python3

rm -rf "${ARTIFACT_DIR}"
mkdir -p "${FIXTURE_DIR}"

cat > "${FIXTURE_DIR}/runtime.json" <<'JSON'
{
  "backend_image_repository_url": {"value": "registry.example.internal/terraformers-backend"},
  "upload_bucket_name": {"value": "terraformers-dev-uploads-example"},
  "result_bucket_name": {"value": "terraformers-dev-results-example"},
  "ai_log_queue_url": {"value": "https://sqs.ap-northeast-2.amazonaws.com/example-account/terraformers-dev-ai-log"},
  "terraform_log_queue_url": {"value": "https://sqs.ap-northeast-2.amazonaws.com/example-account/terraformers-dev-terraform-log"}
}
JSON

cat > "${FIXTURE_DIR}/stateful.json" <<'JSON'
{
  "spring_datasource_url": {"value": "jdbc:mariadb://database.example.internal:3306/terraformers"},
  "database_username": {"value": "terraformers_app"},
  "cognito_region": {"value": "ap-northeast-2"},
  "cognito_user_pool_id": {"value": "ap-northeast-2_examplepool"},
  "cognito_user_pool_client_id": {"value": "exampleclientid"},
  "cognito_jwks_url": {"value": "https://cognito-idp.ap-northeast-2.amazonaws.com/ap-northeast-2_examplepool/.well-known/jwks.json"}
}
JSON

cat > "${FIXTURE_DIR}/eks.json" <<'JSON'
{
  "backend_namespace": {"value": "terraformers-runtime"},
  "backend_irsa_role_arn": {"value": "arn:aws:iam::123456789012:role/terraformers-dev-backend-irsa"}
}
JSON

echo "[aws-runtime-package] building input bundle"
python3 "${REPO_ROOT}/scripts/deploy/build-aws-runtime-input-bundle.py" \
  --runtime-outputs-json "${FIXTURE_DIR}/runtime.json" \
  --stateful-outputs-json "${FIXTURE_DIR}/stateful.json" \
  --eks-outputs-json "${FIXTURE_DIR}/eks.json" \
  --database-password "example-password-not-a-secret" \
  --image-uri "registry.example.internal/terraformers-backend:package-smoke" \
  --output-dir "${INPUT_BUNDLE_DIR}"

echo "[aws-runtime-package] building deployment package"
bash "${REPO_ROOT}/scripts/deploy/build-aws-runtime-deployment-package.sh" \
  --input-dir "${INPUT_BUNDLE_DIR}" \
  --output-dir "${PACKAGE_DIR}" \
  --cluster-check false \
  --server-dry-run false

require_file "${PACKAGE_DIR}/backend-runtime-secret.yaml"
require_file "${PACKAGE_DIR}/aws-runtime-manifest.yaml"
require_file "${PACKAGE_DIR}/preflight-report.txt"
require_file "${PACKAGE_DIR}/apply-order.txt"
require_file "${PACKAGE_DIR}/README.txt"

assert_contains '^kind: Secret$' "${PACKAGE_DIR}/backend-runtime-secret.yaml" "Package must include a rendered Secret."
assert_contains '^type: Opaque$' "${PACKAGE_DIR}/backend-runtime-secret.yaml" "Rendered Secret must explicitly be Opaque."
assert_contains 'name: terraformers-backend-runtime-secrets' "${PACKAGE_DIR}/backend-runtime-secret.yaml" "Rendered Secret must use backend Secret name."
assert_contains '^kind: Deployment$' "${PACKAGE_DIR}/aws-runtime-manifest.yaml" "Runtime manifest must include a Deployment."
assert_contains 'image: registry.example.internal/terraformers-backend:package-smoke' "${PACKAGE_DIR}/aws-runtime-manifest.yaml" "Runtime manifest must include package image."
assert_contains 'eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/terraformers-dev-backend-irsa' "${PACKAGE_DIR}/aws-runtime-manifest.yaml" "Runtime manifest must include IRSA annotation."
assert_contains 'cluster checks and kubectl dry-runs skipped' "${PACKAGE_DIR}/preflight-report.txt" "Static package preflight must skip cluster checks."
assert_contains 'aws-runtime-rollout-smoke.sh' "${PACKAGE_DIR}/apply-order.txt" "Apply order must include rollout smoke command."

assert_not_contains 'registry\.example\.com/terraformers-backend:immutable-tag' "${PACKAGE_DIR}/aws-runtime-manifest.yaml" "Runtime manifest must not keep template image placeholder."
assert_not_contains 'public\.ecr\.aws/example/terraformers-backend' "${PACKAGE_DIR}/aws-runtime-manifest.yaml" "Runtime manifest must not keep base image placeholder."

set +e
bash "${REPO_ROOT}/scripts/deploy/build-aws-runtime-deployment-package.sh" \
  --input-dir "${ARTIFACT_DIR}/missing-input" \
  --output-dir "${ARTIFACT_DIR}/should-not-exist" \
  >"${MISSING_INPUT_OUTPUT}" 2>&1
missing_status=$?
set -e

if [[ ${missing_status} -eq 0 ]]; then
  echo "Package builder must fail when input bundle files are missing." >&2
  exit 1
fi

assert_contains 'Missing required backend runtime Secret env file' "${MISSING_INPUT_OUTPUT}" "Missing input failure must be explicit."

echo "[aws-runtime-package] verification completed"
