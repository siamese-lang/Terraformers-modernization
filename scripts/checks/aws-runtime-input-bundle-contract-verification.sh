#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="${REPO_ROOT}/artifacts/aws-runtime-input-bundle-contract"
FIXTURE_DIR="${EVIDENCE_DIR}/fixtures"
BUNDLE_DIR="${EVIDENCE_DIR}/bundle"
SECRET_MANIFEST="${EVIDENCE_DIR}/backend-runtime-secret.yaml"
SUMMARY="${EVIDENCE_DIR}/verification-summary.txt"

for command_name in python3 kubectl grep awk sort diff; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
done

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${FIXTURE_DIR}"

cat >"${FIXTURE_DIR}/runtime.json" <<'JSON'
{
  "backend_image_repository_url": {
    "value": "123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend"
  },
  "upload_bucket_name": {
    "value": "terraformers-upload-fixture"
  },
  "result_bucket_name": {
    "value": "terraformers-result-fixture"
  },
  "backend_runtime_secret_arn": {
    "value": "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:terraformers-runtime"
  },
  "kubernetes_runtime_secret_name": {
    "value": "terraformers-backend-runtime-secrets"
  }
}
JSON

cat >"${FIXTURE_DIR}/stateful.json" <<'JSON'
{
  "spring_datasource_url": {
    "value": "jdbc:mariadb://database.internal:3306/terraformers?useSsl=true"
  },
  "database_username": {
    "value": "terraformers_app"
  },
  "database_master_user_secret_arn": {
    "value": "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:rds-master"
  },
  "cognito_region": {
    "value": "ap-northeast-2"
  },
  "cognito_user_pool_id": {
    "value": "ap-northeast-2_fixture"
  },
  "cognito_user_pool_client_id": {
    "value": "fixture-client-id"
  },
  "cognito_jwks_url": {
    "value": "https://cognito-idp.ap-northeast-2.amazonaws.com/ap-northeast-2_fixture/.well-known/jwks.json"
  }
}
JSON

cat >"${FIXTURE_DIR}/eks.json" <<'JSON'
{
  "cluster_name": {
    "value": "terraformers-runtime"
  },
  "backend_namespace": {
    "value": "terraformers-runtime"
  },
  "backend_service_account_name": {
    "value": "terraformers-backend"
  },
  "backend_irsa_role_arn": {
    "value": "arn:aws:iam::123456789012:role/terraformers-backend-irsa"
  }
}
JSON

SPRING_DATASOURCE_PASSWORD="fixture-private-password" \
BACKEND_IMAGE_URI="123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend:sha-0123456789abcdef" \
python3 "${REPO_ROOT}/scripts/deploy/build-aws-runtime-input-bundle.py" \
  --runtime-outputs-json "${FIXTURE_DIR}/runtime.json" \
  --stateful-outputs-json "${FIXTURE_DIR}/stateful.json" \
  --eks-outputs-json "${FIXTURE_DIR}/eks.json" \
  --output-dir "${BUNDLE_DIR}"

SECRET_ENV="${BUNDLE_DIR}/backend-runtime-secret.env"
MANIFEST_ENV="${BUNDLE_DIR}/aws-runtime-manifest.env"
SOURCE_MAP="${BUNDLE_DIR}/deployment-source-map.json"
BUNDLE_SUMMARY="${BUNDLE_DIR}/bundle-summary.txt"

for required_file in \
  "${SECRET_ENV}" \
  "${MANIFEST_ENV}" \
  "${SOURCE_MAP}" \
  "${BUNDLE_SUMMARY}" \
  "${BUNDLE_DIR}/apply-order.txt"; do
  test -s "${required_file}"
done

cat >"${EVIDENCE_DIR}/expected-secret-keys.txt" <<'EOF'
ANALYSIS_RESULT_BUCKET_NAME
COGNITO_JWKS_URL
COGNITO_REGION
COGNITO_USER_POOL_CLIENT_ID
COGNITO_USER_POOL_ID
S3_BUCKET_NAME
SPRING_DATASOURCE_PASSWORD
SPRING_DATASOURCE_URL
SPRING_DATASOURCE_USERNAME
EOF

cut -d= -f1 "${SECRET_ENV}" | sort >"${EVIDENCE_DIR}/actual-secret-keys.txt"
diff -u \
  "${EVIDENCE_DIR}/expected-secret-keys.txt" \
  "${EVIDENCE_DIR}/actual-secret-keys.txt"

if grep -Eq \
  '^(AI_LOG_QUEUE_URL|TERRAFORM_LOG_QUEUE_URL|BEDROCK_MODEL_ID|BEDROCK_EMBEDDING_MODEL_ID|OPENSEARCH_ENDPOINT|INDEX_NAME|VECTOR_FIELD_NAME|CONTENT_FIELD_NAME)=' \
  "${SECRET_ENV}"; then
  echo "Base AWS runtime input bundle must not include disabled adapter settings." >&2
  exit 1
fi

grep -qx \
  'BACKEND_IMAGE_URI=123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend:sha-0123456789abcdef' \
  "${MANIFEST_ENV}"
grep -qx \
  'BACKEND_IRSA_ROLE_ARN=arn:aws:iam::123456789012:role/terraformers-backend-irsa' \
  "${MANIFEST_ENV}"
grep -qx 'KUBERNETES_NAMESPACE=terraformers-runtime' "${MANIFEST_ENV}"

grep -q '"runtime_secret_provider_status": "unresolved"' "${SOURCE_MAP}"
grep -q '"database_password_delivery_status": "private-input-required"' "${SOURCE_MAP}"
if grep -q 'fixture-private-password' "${SOURCE_MAP}"; then
  echo "Deployment source map must not contain the database password." >&2
  exit 1
fi

grep -qx 'base_required_key_count=8' "${BUNDLE_SUMMARY}"
grep -qx 'runtime_secret_key_count=9' "${BUNDLE_SUMMARY}"
grep -qx 'optional_adapter_setting_count=0' "${BUNDLE_SUMMARY}"
grep -qx 'backend_image_repository_match=true' "${BUNDLE_SUMMARY}"

bash "${REPO_ROOT}/scripts/deploy/render-backend-runtime-secret.sh" \
  --env-file "${SECRET_ENV}" \
  --namespace terraformers-runtime \
  --output "${SECRET_MANIFEST}"

grep -q '^kind: Secret$' "${SECRET_MANIFEST}"
grep -q '^  name: terraformers-backend-runtime-secrets$' "${SECRET_MANIFEST}"
while IFS= read -r key; do
  grep -q "^  ${key}:" "${SECRET_MANIFEST}"
done <"${EVIDENCE_DIR}/expected-secret-keys.txt"

if grep -Eq \
  '^  (AI_LOG_QUEUE_URL|TERRAFORM_LOG_QUEUE_URL|BEDROCK_MODEL_ID|BEDROCK_EMBEDDING_MODEL_ID|OPENSEARCH_ENDPOINT|INDEX_NAME|VECTOR_FIELD_NAME|CONTENT_FIELD_NAME):' \
  "${SECRET_MANIFEST}"; then
  echo "Rendered base Secret must not include disabled adapter settings." >&2
  exit 1
fi

if SPRING_DATASOURCE_PASSWORD="fixture-private-password" \
  BACKEND_IMAGE_URI="123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/wrong-repository:sha-0123456789abcdef" \
  python3 "${REPO_ROOT}/scripts/deploy/build-aws-runtime-input-bundle.py" \
    --runtime-outputs-json "${FIXTURE_DIR}/runtime.json" \
    --stateful-outputs-json "${FIXTURE_DIR}/stateful.json" \
    --eks-outputs-json "${FIXTURE_DIR}/eks.json" \
    --output-dir "${EVIDENCE_DIR}/invalid-image-bundle" \
    >"${EVIDENCE_DIR}/invalid-image.stdout.txt" \
    2>"${EVIDENCE_DIR}/invalid-image.stderr.txt"; then
  echo "Input bundle must reject an image URI from a different repository." >&2
  exit 1
fi

grep -q 'must belong to Terraform output backend_image_repository_url' \
  "${EVIDENCE_DIR}/invalid-image.stderr.txt"

printf '%s\n' \
  'aws_runtime_input_bundle_contract=passed' \
  'base_required_key_count=8' \
  'runtime_secret_key_count=9' \
  'optional_adapter_setting_count=0' \
  'backend_image_repository_match=true' \
  'secret_render_cluster_contact=none' \
  'runtime_secret_provider=unresolved' \
  >"${SUMMARY}"

cat "${SUMMARY}"
