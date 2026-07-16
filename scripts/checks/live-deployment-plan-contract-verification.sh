#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${REPO_ROOT}/config/live-deployment-stages.json"
GENERATOR="${REPO_ROOT}/scripts/deploy/build-live-deployment-execution-plan.py"
SUMMARIZER="${REPO_ROOT}/scripts/deploy/summarize-terraform-plan.py"
LIVE_WORKFLOW="${REPO_ROOT}/.github/workflows/aws-live-terraform-plan.yml"
DOC="${REPO_ROOT}/docs/live-aws-deployment-execution-plan.md"
EVIDENCE_DIR="${REPO_ROOT}/artifacts/live-deployment-plan-contract"
PLAN_DIR="${EVIDENCE_DIR}/execution-plan"
FIXTURE_DIR="${EVIDENCE_DIR}/fixtures"
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

for command_name in grep python3 sha256sum; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Required command not found: ${command_name}" >&2
    exit 1
  }
done

for required_file in "${MANIFEST}" "${GENERATOR}" "${SUMMARIZER}" "${LIVE_WORKFLOW}" "${DOC}"; do
  test -s "${required_file}" || {
    echo "Expected non-empty file: ${required_file}" >&2
    exit 1
  }
done

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${PLAN_DIR}" "${FIXTURE_DIR}"
python3 -m json.tool "${MANIFEST}" > "${EVIDENCE_DIR}/live-deployment-stages.normalized.json"
python3 "${GENERATOR}" --manifest "${MANIFEST}" --output-dir "${PLAN_DIR}"

python3 - "${MANIFEST}" <<'PY'
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
stages = manifest["stages"]
by_id = {stage["id"]: stage for stage in stages}
assert len(stages) == 12, len(stages)
assert len(by_id) == len(stages)
assert manifest["public_entrypoint"] == "cloudfront-only"
assert manifest["terraform_plan_stages"] == [
    "network",
    "runtime-dependencies",
    "stateful-dependencies",
    "eks-runtime",
    "frontend-delivery",
]
for stage in stages:
    for dependency in stage.get("depends_on", []):
        assert dependency in by_id, (stage["id"], dependency)
    if stage.get("mutation_allowed"):
        assert stage.get("approval_required") is True, stage["id"]
    if stage.get("kind") == "terraform-plan":
        assert stage.get("mutation_allowed") is False, stage["id"]
        assert stage.get("approval_required") is False, stage["id"]
assert "80-private-origin-reconciliation" in by_id["90-frontend-delivery-plan"]["depends_on"]
assert "100-frontend-publish" in by_id["110-e2e-and-incident-evidence"]["depends_on"]
PY

assert_contains '^live_deployment_execution_plan=generated$' "${PLAN_DIR}/plan-summary.txt" "Execution plan generation failed."
assert_contains '^stage_count=12$' "${PLAN_DIR}/plan-summary.txt" "Unexpected deployment stage count."
assert_contains '^terraform_plan_stage_count=5$' "${PLAN_DIR}/plan-summary.txt" "Unexpected Terraform plan stage count."
assert_contains '^approval_required_stage_count=5$' "${PLAN_DIR}/plan-summary.txt" "Unexpected approval stage count."
assert_contains '^public_entrypoint=cloudfront-only$' "${PLAN_DIR}/plan-summary.txt" "CloudFront-only entry point contract changed."
assert_contains '^terraform_apply_automated=false$' "${PLAN_DIR}/plan-summary.txt" "Terraform apply must not be automated."
assert_contains '^terraform_destroy_automated=false$' "${PLAN_DIR}/plan-summary.txt" "Terraform destroy must not be automated."

assert_contains 'execute_live_plan:' "${LIVE_WORKFLOW}" "Live plan workflow needs an explicit execution switch."
assert_contains 'default:[[:space:]]*false' "${LIVE_WORKFLOW}" "Live AWS planning must default to contract-only."
assert_contains 'environment:[[:space:]]*aws-live-plan' "${LIVE_WORKFLOW}" "Live planning must use the protected aws-live-plan environment."
assert_contains 'allowed-account-ids:[[:space:]]*\$\{\{ inputs.expected_aws_account_id \}\}' "${LIVE_WORKFLOW}" "OIDC action must enforce the expected AWS account."
assert_contains 'aws-actions/configure-aws-credentials@v5' "${LIVE_WORKFLOW}" "Live plan must use GitHub OIDC."
assert_not_contains 'secrets\.AWS_ACCESS_KEY_ID|secrets\.AWS_SECRET_ACCESS_KEY' "${LIVE_WORKFLOW}" "Long-lived AWS credential secrets are forbidden."
assert_contains 'terraform -chdir="\$\{TF_DIR\}" plan' "${LIVE_WORKFLOW}" "Saved Terraform plan command is missing."
assert_contains 'terraform -chdir="\$\{TF_DIR\}" show -json' "${LIVE_WORKFLOW}" "Terraform plan JSON must be generated ephemerally for sanitization."
assert_not_contains '(^|[[:space:]])terraform[[:space:]]+(apply|destroy)([[:space:]]|$)' "${LIVE_WORKFLOW}" "Terraform apply/destroy must not exist in the plan workflow."
assert_not_contains 'kubectl[[:space:]]+apply|helm[[:space:]]+(install|upgrade)|aws[[:space:]]+s3[[:space:]]+sync|cloudfront[[:space:]]+create-invalidation' "${LIVE_WORKFLOW}" "Mutation commands must not exist in the plan workflow."
assert_contains 'rm -f .*live-plan\.json.*live\.tfplan.*live\.auto\.tfvars' "${LIVE_WORKFLOW}" "Raw plan and private tfvars must be deleted before artifact upload."
assert_contains 'raw_plan_uploaded=false' "${LIVE_WORKFLOW}" "Evidence must state that raw plans are not uploaded."
assert_not_contains 'path:[[:space:]]*\$\{\{ runner\.temp \}\}|path:[[:space:]].*live-plan\.json|path:[[:space:]].*live\.tfplan' "${LIVE_WORKFLOW}" "Raw plan material must not be uploaded."

cat > "${FIXTURE_DIR}/safe-plan.json" <<'JSON'
{
  "format_version": "1.2",
  "terraform_version": "1.9.8",
  "resource_changes": [
    {
      "address": "aws_vpc.runtime",
      "type": "aws_vpc",
      "change": {"actions": ["create"], "after": {"cidr_block": "10.40.0.0/16"}}
    },
    {
      "address": "aws_s3_bucket_public_access_block.frontend",
      "type": "aws_s3_bucket_public_access_block",
      "change": {"actions": ["create"], "after": {"block_public_acls": true, "block_public_policy": true, "ignore_public_acls": true, "restrict_public_buckets": true}}
    }
  ]
}
JSON
python3 "${SUMMARIZER}" \
  --plan-json "${FIXTURE_DIR}/safe-plan.json" \
  --output-dir "${EVIDENCE_DIR}/safe-plan-summary" \
  --stage network
assert_contains '^terraform_plan_risk_gate=passed$' "${EVIDENCE_DIR}/safe-plan-summary/plan-risk-summary.txt" "Safe fixture plan must pass."
assert_contains '^raw_plan_uploaded=false$' "${EVIDENCE_DIR}/safe-plan-summary/plan-risk-summary.txt" "Sanitized plan evidence boundary changed."

cat > "${FIXTURE_DIR}/destructive-plan.json" <<'JSON'
{
  "format_version": "1.2",
  "terraform_version": "1.9.8",
  "resource_changes": [
    {
      "address": "aws_db_instance.backend",
      "type": "aws_db_instance",
      "change": {"actions": ["delete", "create"], "after": {"publicly_accessible": false}}
    }
  ]
}
JSON
if python3 "${SUMMARIZER}" \
  --plan-json "${FIXTURE_DIR}/destructive-plan.json" \
  --output-dir "${EVIDENCE_DIR}/destructive-plan-summary" \
  --stage stateful-dependencies; then
  echo 'Destructive fixture plan unexpectedly passed.' >&2
  exit 1
fi
assert_contains '^destructive_resource_count=1$' "${EVIDENCE_DIR}/destructive-plan-summary/plan-risk-summary.txt" "Destructive resource was not detected."
assert_contains 'failure_reasons=destructive-action' "${EVIDENCE_DIR}/destructive-plan-summary/plan-risk-summary.txt" "Destructive failure reason is missing."

cat > "${FIXTURE_DIR}/public-plan.json" <<'JSON'
{
  "format_version": "1.2",
  "terraform_version": "1.9.8",
  "resource_changes": [
    {
      "address": "aws_lb.backend",
      "type": "aws_lb",
      "change": {"actions": ["create"], "after": {"internal": false}}
    }
  ]
}
JSON
if python3 "${SUMMARIZER}" \
  --plan-json "${FIXTURE_DIR}/public-plan.json" \
  --output-dir "${EVIDENCE_DIR}/public-plan-summary" \
  --stage eks-runtime; then
  echo 'Public exposure fixture plan unexpectedly passed.' >&2
  exit 1
fi
assert_contains '^public_exposure_finding_count=1$' "${EVIDENCE_DIR}/public-plan-summary/plan-risk-summary.txt" "Public load balancer was not detected."
assert_contains 'failure_reasons=public-exposure' "${EVIDENCE_DIR}/public-plan-summary/plan-risk-summary.txt" "Public exposure failure reason is missing."

cat > "${FIXTURE_DIR}/optional-adapter-plan.json" <<'JSON'
{
  "format_version": "1.2",
  "terraform_version": "1.9.8",
  "resource_changes": [
    {
      "address": "aws_opensearchserverless_collection.analysis",
      "type": "aws_opensearchserverless_collection",
      "change": {"actions": ["create"], "after": {"name": "analysis"}}
    }
  ]
}
JSON
if python3 "${SUMMARIZER}" \
  --plan-json "${FIXTURE_DIR}/optional-adapter-plan.json" \
  --output-dir "${EVIDENCE_DIR}/optional-adapter-plan-summary" \
  --stage runtime-dependencies; then
  echo 'Optional adapter fixture plan unexpectedly passed.' >&2
  exit 1
fi
assert_contains '^optional_adapter_resource_count=1$' "${EVIDENCE_DIR}/optional-adapter-plan-summary/plan-risk-summary.txt" "Optional adapter resource was not detected."
assert_contains 'failure_reasons=optional-adapter' "${EVIDENCE_DIR}/optional-adapter-plan-summary/plan-risk-summary.txt" "Optional adapter failure reason is missing."

assert_contains 'CloudFront VPC origin' "${DOC}" "Deployment documentation must preserve the private origin architecture."
assert_contains 'terraform apply' "${DOC}" "Deployment documentation must state the apply approval boundary."
assert_contains 'AWS_TERRAFORM_STATE_BUCKET' "${DOC}" "State backend prerequisite is not documented."
assert_contains 'AWS_LIVE_NETWORK_TFVARS_B64' "${DOC}" "Private stage tfvars contract is not documented."
assert_contains 'raw plan' "${DOC}" "Sensitive raw-plan evidence boundary is not documented."

printf '%s\n' \
  'live_deployment_plan_contract=passed' \
  'stage_count=12' \
  'terraform_plan_stage_count=5' \
  'plan_workflow=guarded-oidc' \
  'environment_gate=aws-live-plan' \
  'expected_account_check=required' \
  'remote_state_versioning=required' \
  'remote_state_lock_table=required' \
  'destructive_action_default=blocked' \
  'public_exposure=blocked' \
  'optional_adapter_default=blocked' \
  'raw_plan_uploaded=false' \
  'terraform_apply_automated=false' \
  'terraform_destroy_automated=false' \
  'aws_mutation=none' \
  > "${SUMMARY}"
cat "${SUMMARY}"
