#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_PROD="${REPO_ROOT}/backend/src/main/resources/application-prod.yml"
ADAPTER_VALIDATOR="${REPO_ROOT}/backend/src/main/java/com/terraformers/modernization/config/RuntimeAdapterContractValidator.java"
SECRET_EXAMPLE="${REPO_ROOT}/infra/kubernetes/base/backend-secret.example.yaml"
CONFIGMAP="${REPO_ROOT}/infra/kubernetes/base/backend-configmap.yaml"
AWS_OVERLAY="${REPO_ROOT}/infra/kubernetes/overlays/aws-runtime-template"
FRONTEND_ENV="${REPO_ROOT}/frontend/.env.example"
EVIDENCE_DIR="${REPO_ROOT}/artifacts/aws-environment-contract"
RENDERED_AWS="${EVIDENCE_DIR}/kubernetes-aws-runtime-template.yaml"
SUMMARY="${EVIDENCE_DIR}/verification-summary.txt"

for command_name in python3 kubectl; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
    exit 1
  fi
done

for required_file in \
  "${APP_PROD}" \
  "${ADAPTER_VALIDATOR}" \
  "${SECRET_EXAMPLE}" \
  "${CONFIGMAP}" \
  "${FRONTEND_ENV}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Required contract file not found: ${required_file}" >&2
    exit 1
  fi
done

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${EVIDENCE_DIR}"

kubectl kustomize "${AWS_OVERLAY}" >"${RENDERED_AWS}"
test -s "${RENDERED_AWS}"
kubectl version --client --output=yaml >"${EVIDENCE_DIR}/kubectl-client-version.yaml"

python3 - \
  "${APP_PROD}" \
  "${ADAPTER_VALIDATOR}" \
  "${SECRET_EXAMPLE}" \
  "${CONFIGMAP}" \
  "${FRONTEND_ENV}" \
  "${RENDERED_AWS}" \
  "${SUMMARY}" <<'PY'
from pathlib import Path
import re
import sys

(
    app_path,
    validator_path,
    secret_path,
    configmap_path,
    frontend_path,
    rendered_path,
    summary_path,
) = map(Path, sys.argv[1:])

app = app_path.read_text(encoding="utf-8")
validator = validator_path.read_text(encoding="utf-8")
secret = secret_path.read_text(encoding="utf-8")
configmap = configmap_path.read_text(encoding="utf-8")
frontend = frontend_path.read_text(encoding="utf-8")
rendered = rendered_path.read_text(encoding="utf-8")

base_required = [
    "SPRING_DATASOURCE_URL",
    "SPRING_DATASOURCE_USERNAME",
    "SPRING_DATASOURCE_PASSWORD",
    "COGNITO_REGION",
    "COGNITO_USER_POOL_ID",
    "COGNITO_USER_POOL_CLIENT_ID",
    "COGNITO_JWKS_URL",
    "S3_BUCKET_NAME",
]
optional_secret_keys = [
    "ANALYSIS_RESULT_BUCKET_NAME",
    "BEDROCK_MODEL_ID",
    "BEDROCK_EMBEDDING_MODEL_ID",
    "OPENSEARCH_ENDPOINT",
    "INDEX_NAME",
    "VECTOR_FIELD_NAME",
    "CONTENT_FIELD_NAME",
    "AI_LOG_QUEUE_URL",
    "TERRAFORM_LOG_QUEUE_URL",
]
adapter_switches = [
    "S3_READER_ENABLED",
    "S3_WRITER_ENABLED",
    "BEDROCK_PROVIDER_ENABLED",
    "BEDROCK_EMBEDDING_ENABLED",
    "OPENSEARCH_RETRIEVER_ENABLED",
    "ANALYSIS_SQS_PUBLISHER_ENABLED",
]
frontend_expected = [
    "REACT_APP_API_BASE_URL",
    "REACT_APP_AWS_REGION",
    "REACT_APP_COGNITO_USER_POOL_ID",
    "REACT_APP_COGNITO_USER_POOL_CLIENT_ID",
]
legacy_server_keys = {
    "AWS_S3_BUCKET_NAME",
    "FRONTEND_URL",
    "DOMAIN",
}

errors: list[str] = []

required_match = re.search(
    r"(?ms)^\s{4}required-env:\s*\n((?:\s{6}- [A-Z0-9_]+\s*\n?)+)",
    app,
)
if not required_match:
    errors.append("application-prod.yml required-env block was not found")
    app_required: list[str] = []
else:
    app_required = re.findall(r"^\s{6}- ([A-Z0-9_]+)\s*$", required_match.group(1), re.M)
    if app_required != base_required:
        errors.append(
            "application-prod.yml required-env differs from the canonical base contract: "
            f"expected={base_required}, actual={app_required}"
        )

active_secret_keys = re.findall(r"^\s{2}([A-Z][A-Z0-9_]+):", secret, re.M)
missing_base_secret = [key for key in base_required if key not in active_secret_keys]
if missing_base_secret:
    errors.append(f"Secret example is missing base keys: {missing_base_secret}")
unknown_active_secret = [
    key
    for key in active_secret_keys
    if key not in set(base_required + ["ANALYSIS_RESULT_BUCKET_NAME"])
]
if unknown_active_secret:
    errors.append(f"Secret example has unexpected active keys: {unknown_active_secret}")
for key in optional_secret_keys:
    if key not in secret:
        errors.append(f"Secret example does not document optional key: {key}")
for key in legacy_server_keys:
    if re.search(rf"^\s{{2}}{re.escape(key)}:", secret, re.M):
        errors.append(f"Legacy server key is active in Secret example: {key}")

config_values = dict(
    re.findall(r'^\s{2}([A-Z][A-Z0-9_]+):\s*"?([^"\n]+)"?\s*$', configmap, re.M)
)
if config_values.get("SPRING_PROFILES_ACTIVE") != "prod":
    errors.append("Base ConfigMap must use SPRING_PROFILES_ACTIVE=prod")
for switch in adapter_switches:
    if config_values.get(switch) != "false":
        errors.append(f"Base ConfigMap adapter switch must remain false: {switch}")

for required_literal in [
    'requireText(missing, "BEDROCK_MODEL_ID"',
    'requireText(missing, "BEDROCK_EMBEDDING_MODEL_ID"',
    'requireText(missing, "OPENSEARCH_ENDPOINT"',
    'requireText(missing, "INDEX_NAME"',
    'requireText(missing, "VECTOR_FIELD_NAME"',
    'requireText(missing, "CONTENT_FIELD_NAME"',
    'requireText(missing, "AI_LOG_QUEUE_URL"',
    'requireText(missing, "TERRAFORM_LOG_QUEUE_URL"',
]:
    if required_literal not in validator:
        errors.append(f"Adapter validator mapping is missing: {required_literal}")

frontend_keys = re.findall(r"^(REACT_APP_[A-Z0-9_]+)=", frontend, re.M)
if frontend_keys != frontend_expected:
    errors.append(
        "frontend/.env.example differs from the canonical browser contract: "
        f"expected={frontend_expected}, actual={frontend_keys}"
    )
for server_secret in base_required + optional_secret_keys:
    if server_secret in frontend:
        errors.append(f"Server runtime key leaked into frontend contract: {server_secret}")

for required_rendered in [
    "namespace: terraformers-runtime",
    "serviceAccountName: terraformers-backend",
    "name: terraformers-backend-runtime-config",
    "name: terraformers-backend-runtime-secrets",
    "SPRING_PROFILES_ACTIVE: prod",
    "image: registry.example.com/terraformers-backend:immutable-tag",
]:
    if required_rendered not in rendered:
        errors.append(f"AWS overlay is missing rendered contract: {required_rendered}")
if re.search(r"(?m)^kind: Secret$", rendered):
    errors.append("AWS public runtime template must not render a Secret resource")
if re.search(r"(?m)^\s*image: .*:latest\s*$", rendered):
    errors.append("AWS runtime template must not use a mutable latest image tag")

summary_lines = [
    "aws_environment_contract=passed" if not errors else "aws_environment_contract=failed",
    f"base_required_env_count={len(app_required)}",
    f"active_secret_key_count={len(active_secret_keys)}",
    f"frontend_build_variable_count={len(frontend_keys)}",
    "aws_overlay_cluster_contact=none",
    "terraform_output_mapping=unresolved",
    "github_variable_mapping=unresolved",
    "service_account_irsa=unresolved",
    "runtime_secret_provider=unresolved",
]
summary_path.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

if errors:
    for error in errors:
        print(f"[aws-environment-contract] {error}", file=sys.stderr)
    raise SystemExit(1)

print("[aws-environment-contract] application, Kubernetes, and frontend contracts are aligned")
PY

cat "${SUMMARY}"
