#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTERED_ENTRY="${REPO_ROOT}/.github/workflows/runtime-contract-verification.yml"
POST_MERGE_WORKFLOW="${REPO_ROOT}/.github/workflows/aws-live-terraform-plan.yml"
SUMMARY="${REPO_ROOT}/artifacts/live-deployment-plan-contract/premerge-dispatch-summary.txt"

for file in "${REGISTERED_ENTRY}" "${POST_MERGE_WORKFLOW}"; do
  test -s "${file}" || {
    echo "Expected non-empty workflow file: ${file}" >&2
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

assert_contains '^on:$' "${REGISTERED_ENTRY}" 'Registered dispatch entry is missing the on block.'
assert_contains '^[[:space:]]+workflow_dispatch:' "${REGISTERED_ENTRY}" 'Registered dispatch entry must retain workflow_dispatch.'
assert_contains 'live-deployment-execution-plan:' "${REGISTERED_ENTRY}" 'Registered runtime workflow must expose the pre-merge execution-plan job.'
assert_contains 'build-live-deployment-execution-plan\.py' "${REGISTERED_ENTRY}" 'Pre-merge entry must generate the canonical execution plan.'
assert_contains 'name:[[:space:]]+live-deployment-execution-plan-evidence' "${REGISTERED_ENTRY}" 'Pre-merge entry must upload the execution-plan artifact.'
assert_contains '^[[:space:]]+workflow_dispatch:' "${POST_MERGE_WORKFLOW}" 'Post-merge direct workflow must remain manually dispatchable after registration on main.'

mkdir -p "$(dirname "${SUMMARY}")"
printf '%s\n' \
  'premerge_live_plan_dispatch_contract=passed' \
  'registered_dispatch_entry=runtime-contract-verification.yml' \
  'premerge_execution_plan_job=present' \
  'direct_live_plan_workflow_requires_default_branch_registration=true' \
  'aws_authentication=none' \
  'aws_mutation=none' \
  > "${SUMMARY}"
cat "${SUMMARY}"
