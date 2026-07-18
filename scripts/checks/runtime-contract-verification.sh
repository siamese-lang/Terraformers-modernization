#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/backend"
BACKEND_MAIN_DIR="${BACKEND_DIR}/src/main"
K8S_BASE_DIR="${REPO_ROOT}/infra/kubernetes/base"
K8S_LOCAL_STUB_OVERLAY_DIR="${REPO_ROOT}/infra/kubernetes/overlays/local-stub"
K8S_AWS_RUNTIME_TEMPLATE_DIR="${REPO_ROOT}/infra/kubernetes/overlays/aws-runtime-template"
TERRAFORM_CONTRACT_DIR="${REPO_ROOT}/infra/terraform/runtime-contract"
RENDERED_MANIFEST="$(mktemp)"
RENDERED_LOCAL_STUB_MANIFEST="$(mktemp)"
RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST="$(mktemp)"
PLAN_FILE="$(mktemp)"

cleanup() {
  rm -f "${RENDERED_MANIFEST}" "${RENDERED_LOCAL_STUB_MANIFEST}" "${RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST}" "${PLAN_FILE}"
}
trap cleanup EXIT

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}" >&2
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

assert_repository_not_contains() {
  local pattern="$1"
  local directory="$2"
  local message="$3"
  if grep -R -E -n -q "${pattern}" "${directory}"; then
    echo "${message}" >&2
    grep -R -E -n "${pattern}" "${directory}" >&2 || true
    exit 1
  fi
}

assert_kustomization_resource_not_included() {
  local resource_name="$1"
  local kustomization_file="$2"

  # Check only YAML list entries, not explanatory comments.
  if grep -E -q "^[[:space:]]*-[[:space:]]*${resource_name}[[:space:]]*$" "${kustomization_file}"; then
    echo "${resource_name} must not be included in base kustomization resources." >&2
    exit 1
  fi
}

require_command kubectl
require_command terraform
require_command mvn
require_command grep
require_command python3

cd "${REPO_ROOT}"

echo "[runtime-contract] verifying persistence guardrails"
bash scripts/checks/flyway-migration-uniqueness.sh
python3 scripts/checks/terraform-plan-public-cidr-regression-verification.py
assert_repository_not_contains \
  'project_metadata_compat|project_comments' \
  "${BACKEND_MAIN_DIR}" \
  "Removed compatibility persistence models must not reappear in backend main sources or migrations."

echo "[runtime-contract] rendering Kubernetes base"
kubectl kustomize "${K8S_BASE_DIR}" > "${RENDERED_MANIFEST}"

assert_contains '^kind: ConfigMap$' "${RENDERED_MANIFEST}" "Rendered manifest must contain ConfigMap."
assert_contains '^kind: Deployment$' "${RENDERED_MANIFEST}" "Rendered manifest must contain Deployment."
assert_contains '^kind: ServiceAccount$' "${RENDERED_MANIFEST}" "Rendered manifest must contain ServiceAccount."
assert_contains '^kind: Service$' "${RENDERED_MANIFEST}" "Rendered manifest must contain Service."
assert_contains 'S3_READER_ENABLED' "${RENDERED_MANIFEST}" "Rendered manifest must include adapter switches."
assert_contains 'ANALYSIS_SQS_PUBLISHER_ENABLED' "${RENDERED_MANIFEST}" "Rendered manifest must include SQS adapter switch."
assert_contains 'terraformers-backend-runtime-secrets' "${RENDERED_MANIFEST}" "Deployment must reference runtime Secret by name."

assert_not_contains '^kind: Secret$' "${RENDERED_MANIFEST}" "Base kustomization must not render placeholder Secret resources."
assert_not_contains 'arn:aws:iam::[0-9]{12}:' "${RENDERED_MANIFEST}" "Base manifest must not contain account-specific IAM ARNs."
assert_not_contains '[0-9]{12}' "${RENDERED_MANIFEST}" "Base manifest must not contain 12-digit account-like identifiers."
assert_not_contains 'replace-me' "${RENDERED_MANIFEST}" "Base rendered manifest must not contain replace-me placeholders."

assert_kustomization_resource_not_included 'backend-secret.example.yaml' "${K8S_BASE_DIR}/kustomization.yaml"

echo "[runtime-contract] rendering Kubernetes local-stub overlay"
kubectl kustomize "${K8S_LOCAL_STUB_OVERLAY_DIR}" > "${RENDERED_LOCAL_STUB_MANIFEST}"

assert_contains 'namespace: terraformers-local' "${RENDERED_LOCAL_STUB_MANIFEST}" "Local-stub overlay must render into terraformers-local namespace."
assert_contains 'SPRING_PROFILES_ACTIVE: local' "${RENDERED_LOCAL_STUB_MANIFEST}" "Local-stub overlay must run the backend with local profile."
assert_contains 'image: terraformers-backend:local-stub' "${RENDERED_LOCAL_STUB_MANIFEST}" "Local-stub overlay must use the local backend image tag."
assert_contains 'imagePullPolicy: Never' "${RENDERED_LOCAL_STUB_MANIFEST}" "Local-stub overlay must use a preloaded local image."
assert_not_contains 'terraformers-backend-runtime-secrets' "${RENDERED_LOCAL_STUB_MANIFEST}" "Local-stub overlay must not require runtime Secret injection."
assert_not_contains '^kind: Secret$' "${RENDERED_LOCAL_STUB_MANIFEST}" "Local-stub overlay must not render placeholder Secret resources."

echo "[runtime-contract] rendering Kubernetes AWS runtime template overlay"
kubectl kustomize "${K8S_AWS_RUNTIME_TEMPLATE_DIR}" > "${RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST}"

assert_contains 'namespace: terraformers-runtime' "${RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST}" "AWS runtime template must render into terraformers-runtime namespace."
assert_contains 'SPRING_PROFILES_ACTIVE: prod' "${RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST}" "AWS runtime template must run the backend with prod profile."
assert_contains 'AWS_REGION: ap-northeast-2' "${RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST}" "AWS runtime template must include an explicit AWS region."
assert_contains 'image: registry.example.com/terraformers-backend:immutable-tag' "${RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST}" "AWS runtime template must expose where an immutable registry image URI is supplied."
assert_contains 'terraformers-backend-runtime-secrets' "${RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST}" "AWS runtime template must keep runtime Secret injection enabled."
assert_not_contains '^kind: Secret$' "${RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST}" "AWS runtime template must not render placeholder Secret resources."
assert_not_contains 'arn:aws:iam::[0-9]{12}:' "${RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST}" "AWS runtime template must not contain account-specific IAM ARNs."
assert_not_contains '[0-9]{12}' "${RENDERED_AWS_RUNTIME_TEMPLATE_MANIFEST}" "AWS runtime template must not contain 12-digit account-like identifiers."

echo "[runtime-contract] checking committed example files for public-safe placeholders"
assert_not_contains '[0-9]{12}' "${K8S_BASE_DIR}/backend-secret.example.yaml" "Secret example must not contain 12-digit account-like identifiers."
assert_not_contains '[0-9]{12}' "${TERRAFORM_CONTRACT_DIR}/terraform.tfvars.example" "Terraform tfvars example must not contain 12-digit account-like identifiers."
assert_not_contains 'arn:aws:iam::[0-9]{12}:' "${K8S_BASE_DIR}/backend-serviceaccount.yaml" "ServiceAccount base must not contain account-specific IAM ARN."

echo "[runtime-contract] verifying canonical backend API contract flow"
cd "${BACKEND_DIR}"
mvn -q -Dtest=AnalysisUploadControllerTest,AnalysisJobControllerIntegrationTest,ProjectMetadataControllerTest,ProjectTreeControllerTest,TerraformDraftControllerTest,ProjectCommentControllerTest,SourceObjectReaderServiceTest test

echo "[runtime-contract] validating Terraform runtime contract"
cd "${TERRAFORM_CONTRACT_DIR}"
terraform init -backend=false -input=false >/dev/null
terraform fmt -check
terraform validate
terraform plan -input=false -lock=false -var-file=terraform.tfvars.example -out="${PLAN_FILE}" >/dev/null

echo "[runtime-contract] verification completed"
