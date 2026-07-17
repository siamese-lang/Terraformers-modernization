#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTERED_ENTRY="${REPO_ROOT}/.github/workflows/runtime-contract-verification.yml"
REUSABLE_LIVE_PLAN="${REPO_ROOT}/.github/workflows/aws-live-terraform-plan.yml"
DISPATCH_SCRIPT="${REPO_ROOT}/scripts/deploy/dispatch-premerge-network-plan.sh"
SUMMARY="${REPO_ROOT}/artifacts/live-deployment-plan-contract/premerge-dispatch-summary.txt"

for file in "${REGISTERED_ENTRY}" "${REUSABLE_LIVE_PLAN}" "${DISPATCH_SCRIPT}"; do
  test -s "${file}" || {
    echo "Expected non-empty pre-merge dispatch file: ${file}" >&2
    exit 1
  }
done

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

assert_contains '^on:$' "${REGISTERED_ENTRY}" 'Registered dispatch entry is missing the on block.'
assert_contains '^[[:space:]]+workflow_dispatch:' "${REGISTERED_ENTRY}" 'Registered dispatch entry must retain workflow_dispatch.'
assert_contains 'execute_live_plan:' "${REGISTERED_ENTRY}" 'Registered entry must expose the guarded live-plan switch.'
assert_contains 'premerge-live-terraform-plan:' "${REGISTERED_ENTRY}" 'Registered entry must expose the pre-merge live-plan caller job.'
assert_contains 'uses:[[:space:]]+\./\.github/workflows/aws-live-terraform-plan\.yml' "${REGISTERED_ENTRY}" 'Pre-merge caller must use the same-commit live-plan workflow.'
assert_contains 'id-token:[[:space:]]+write' "${REGISTERED_ENTRY}" 'Pre-merge caller must grant OIDC token permission.'
assert_contains 'secrets:[[:space:]]+inherit' "${REGISTERED_ENTRY}" 'Pre-merge caller must inherit protected environment Secret access.'
assert_contains 'live-deployment-execution-plan:' "${REGISTERED_ENTRY}" 'Registered runtime workflow must retain the execution-plan job.'

assert_contains '^[[:space:]]+workflow_dispatch:' "${REUSABLE_LIVE_PLAN}" 'Live plan must remain directly dispatchable after merge.'
assert_contains '^[[:space:]]+workflow_call:' "${REUSABLE_LIVE_PLAN}" 'Live plan must be reusable before merge.'
assert_contains 'environment:[[:space:]]*aws-live-plan' "${REUSABLE_LIVE_PLAN}" 'Reusable live plan must retain the protected environment.'
assert_not_contains '(^|[[:space:]])terraform[[:space:]]+(apply|destroy)([[:space:]]|$)' "${REUSABLE_LIVE_PLAN}" 'Pre-merge plan path must not contain Terraform apply/destroy.'

assert_contains 'inventory-live-aws-prerequisites\.sh' "${DISPATCH_SCRIPT}" 'Dispatch must run strict prerequisites first.'
assert_contains '--stage network' "${DISPATCH_SCRIPT}" 'Dispatch must be limited to the network stage.'
assert_contains '--strict' "${DISPATCH_SCRIPT}" 'Dispatch must require strict prerequisites.'
assert_contains 'execute_live_plan=true' "${DISPATCH_SCRIPT}" 'Dispatch must explicitly enable live planning.'
assert_contains 'allow_destructive=false' "${DISPATCH_SCRIPT}" 'Destructive findings must remain blocked.'
assert_contains 'allow_optional_adapters=false' "${DISPATCH_SCRIPT}" 'Optional adapters must remain blocked.'
assert_contains 'ExpectedAccountIdPrinted=false' "${DISPATCH_SCRIPT}" 'Dispatch evidence must confirm account ID redaction.'
assert_contains 'TerraformApplyExecuted=false' "${DISPATCH_SCRIPT}" 'Dispatch evidence must confirm no apply.'

mkdir -p "$(dirname "${SUMMARY}")"
printf '%s\n' \
  'premerge_live_plan_dispatch_contract=passed' \
  'registered_dispatch_entry=runtime-contract-verification.yml' \
  'reusable_live_plan_workflow=aws-live-terraform-plan.yml' \
  'same_commit_reusable_workflow=true' \
  'network_prerequisite_strict=true' \
  'environment_gate=aws-live-plan' \
  'destructive_action_default=blocked' \
  'optional_adapter_default=blocked' \
  'terraform_apply_automated=false' \
  'terraform_destroy_automated=false' \
  'aws_mutation=read-only-plan' \
  > "${SUMMARY}"
cat "${SUMMARY}"
