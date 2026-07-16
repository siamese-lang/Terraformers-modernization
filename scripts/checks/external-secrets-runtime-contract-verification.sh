#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="${REPO_ROOT}/artifacts/external-secrets-runtime-contract"
FIXTURE_DIR="${EVIDENCE_DIR}/fixtures"
PACKAGE_DIR="${EVIDENCE_DIR}/package"
SUMMARY="${EVIDENCE_DIR}/verification-summary.txt"

for command_name in python3 grep awk sort diff; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
done

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${FIXTURE_DIR}"

cat >"${FIXTURE_DIR}/runtime.json" <<'JSON'
{
  "backend_runtime_secret_arn": {"value": "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:terraformers-runtime"},
  "kubernetes_runtime_secret_name": {"value": "terraformers-backend-runtime-secrets"},
  "upload_bucket_name": {"value": "terraformers-upload-fixture"},
  "result_bucket_name": {"value": "terraformers-result-fixture"}
}
JSON

cat >"${FIXTURE_DIR}/stateful.json" <<'JSON'
{
  "database_master_user_secret_arn": {"value": "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:terraformers-rds"},
  "spring_datasource_url": {"value": "jdbc:mariadb://database.internal:3306/terraformers?useSsl=true"},
  "database_username": {"value": "terraformers_app"},
  "cognito_region": {"value": "ap-northeast-2"},
  "cognito_user_pool_id": {"value": "ap-northeast-2_fixture"},
  "cognito_user_pool_client_id": {"value": "fixture-client-id"},
  "cognito_jwks_url": {"value": "https://cognito-idp.ap-northeast-2.amazonaws.com/ap-northeast-2_fixture/.well-known/jwks.json"}
}
JSON

cat >"${FIXTURE_DIR}/eks.json" <<'JSON'
{
  "aws_region": {"value": "ap-northeast-2"},
  "backend_namespace": {"value": "terraformers-runtime"},
  "external_secrets_service_account_name": {"value": "terraformers-external-secrets"},
  "external_secrets_irsa_role_arn": {"value": "arn:aws:iam::123456789012:role/terraformers-external-secrets"}
}
JSON

python3 "${REPO_ROOT}/scripts/deploy/build-external-secrets-runtime-package.py" \
  --runtime-outputs-json "${FIXTURE_DIR}/runtime.json" \
  --stateful-outputs-json "${FIXTURE_DIR}/stateful.json" \
  --eks-outputs-json "${FIXTURE_DIR}/eks.json" \
  --output-dir "${PACKAGE_DIR}"

PAYLOAD="${PACKAGE_DIR}/backend-runtime-secret-payload.json"
MANIFEST="${PACKAGE_DIR}/external-secrets-runtime.yaml"
SOURCE_MAP="${PACKAGE_DIR}/managed-secret-source-map.json"
PACKAGE_SUMMARY="${PACKAGE_DIR}/package-summary.txt"

for required_file in "${PAYLOAD}" "${MANIFEST}" "${SOURCE_MAP}" "${PACKAGE_SUMMARY}" "${PACKAGE_DIR}/apply-order.txt"; do
  test -s "${required_file}"
done

python3 - "${PAYLOAD}" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected = [
    "SPRING_DATASOURCE_URL",
    "SPRING_DATASOURCE_USERNAME",
    "COGNITO_REGION",
    "COGNITO_USER_POOL_ID",
    "COGNITO_USER_POOL_CLIENT_ID",
    "COGNITO_JWKS_URL",
    "S3_BUCKET_NAME",
    "ANALYSIS_RESULT_BUCKET_NAME",
]
if list(payload) != expected:
    raise SystemExit(f"Unexpected runtime payload keys: {list(payload)}")
if "SPRING_DATASOURCE_PASSWORD" in payload:
    raise SystemExit("RDS-managed password must not be copied into the runtime config payload.")
PY

grep -qx 'apiVersion: external-secrets.io/v1' "${MANIFEST}"
if grep -q 'external-secrets.io/v1beta1' "${MANIFEST}"; then
  echo "Managed Secret package must not reuse the legacy v1beta1 API." >&2
  exit 1
fi
grep -q '^  name: terraformers-external-secrets$' "${MANIFEST}"
grep -q '^  namespace: terraformers-runtime$' "${MANIFEST}"
grep -q 'eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/terraformers-external-secrets"' "${MANIFEST}"
grep -q '^  name: terraformers-backend-secretsmanager$' "${MANIFEST}"
grep -q '^    name: terraformers-backend-runtime-secrets$' "${MANIFEST}"
grep -q 'key: "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:terraformers-rds"' "${MANIFEST}"
grep -q '^        property: password$' "${MANIFEST}"

secret_key_count="$(grep -c '^    - secretKey:' "${MANIFEST}")"
if [[ "${secret_key_count}" != "9" ]]; then
  echo "Expected 9 target Secret keys, found ${secret_key_count}." >&2
  exit 1
fi

if grep -Eq '(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_S3_BUCKET_NAME|FRONTEND_URL|DOMAIN|AI_LOG_QUEUE_URL|TERRAFORM_LOG_QUEUE_URL|BEDROCK_MODEL_ID|OPENSEARCH_ENDPOINT)' "${PAYLOAD}" "${MANIFEST}"; then
  echo "Managed Secret package contains legacy, static credential, or disabled adapter settings." >&2
  exit 1
fi

grep -q '"provider": "external-secrets-operator"' "${SOURCE_MAP}"
grep -q '"provider_installation_status": "required-not-performed"' "${SOURCE_MAP}"
grep -q '"database_password_property": "password"' "${SOURCE_MAP}"
if grep -q 'fixture-private-password' "${SOURCE_MAP}" "${MANIFEST}" "${PAYLOAD}"; then
  echo "Managed Secret evidence must not contain a copied database password." >&2
  exit 1
fi

grep -qx 'runtime_config_key_count=8' "${PACKAGE_SUMMARY}"
grep -qx 'target_secret_key_count=9' "${PACKAGE_SUMMARY}"
grep -qx 'database_password_source=rds-managed-secret/password' "${PACKAGE_SUMMARY}"
grep -qx 'database_password_in_payload=false' "${PACKAGE_SUMMARY}"
grep -qx 'provider_installation=required-not-performed' "${PACKAGE_SUMMARY}"
grep -qx 'cluster_contact=none' "${PACKAGE_SUMMARY}"

cp "${PACKAGE_SUMMARY}" "${SUMMARY}"
printf '%s\n' 'managed_secret_delivery_contract=passed' >>"${SUMMARY}"
cat "${SUMMARY}"
