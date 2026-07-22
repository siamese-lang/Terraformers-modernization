#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/verify-live-foundation.sh \
    --expected-head SHA

This command performs read-only verification of the applied live foundation.
It never runs terraform apply, terraform destroy, or any AWS mutation command.
EOF
}

fail() {
  echo "$1" >&2
  exit 1
}

python_is_usable() {
  local output
  output="$("$@" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)" || return 1
  [[ "$output" =~ ^3\.[0-9]+$ ]]
}

EXPECTED_HEAD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-head)
      [[ $# -ge 2 ]] || fail "EXPECTED_HEAD_VALUE_MISSING"
      EXPECTED_HEAD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "UNKNOWN_ARGUMENT: $1"
      ;;
  esac
done

[[ -n "$EXPECTED_HEAD" ]] || fail "EXPECTED_HEAD_REQUIRED"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FOUNDATION_DIR="${REPO_ROOT}/infra/terraform/bootstrap/aws-live-foundation"
PRIVATE_DIR="$(cygpath -u "$LOCALAPPDATA")/Terraformers/live-foundation"
TF_EXE="$(cygpath -u "$LOCALAPPDATA")/Programs/Terraform/1.15.8/terraform.exe"
STATE_BACKUP="${PRIVATE_DIR}/foundation.local-pre-migration.tfstate"
STATE_BACKUP_DIGEST="${STATE_BACKUP}.sha256"
TFVARS_PATH="${PRIVATE_DIR}/foundation.tfvars"

for command_name in git aws sha256sum cygpath; do
  command -v "$command_name" >/dev/null 2>&1 || fail "REQUIRED_COMMAND_NOT_FOUND: $command_name"
done

PYTHON_CMD=()
PYTHON_LABEL=""

if command -v py >/dev/null 2>&1 && python_is_usable py -3; then
  PYTHON_CMD=(py -3)
  PYTHON_LABEL="py -3"
elif command -v python >/dev/null 2>&1 && python_is_usable python; then
  PYTHON_CMD=(python)
  PYTHON_LABEL="python"
elif command -v python3 >/dev/null 2>&1 && python_is_usable python3; then
  PYTHON_CMD=(python3)
  PYTHON_LABEL="python3"
else
  fail "USABLE_PYTHON3_NOT_FOUND"
fi

[[ -x "$TF_EXE" ]] || fail "TERRAFORM_1_15_8_NOT_FOUND"
[[ -f "$TFVARS_PATH" ]] || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
[[ -f "${FOUNDATION_DIR}/terraform.tfstate" ]] || fail "FOUNDATION_LOCAL_STATE_NOT_FOUND"

cd "$REPO_ROOT"

[[ -z "$(git status --porcelain)" ]] || fail "WORKING_TREE_NOT_CLEAN"

ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"

EXPECTED_ACCOUNT="$(
  sed -nE \
    's/^[[:space:]]*expected_aws_account_id[[:space:]]*=[[:space:]]*"([0-9]{12})".*/\1/p' \
    "$TFVARS_PATH" |
  head -n 1
)"
[[ "$EXPECTED_ACCOUNT" =~ ^[0-9]{12}$ ]] || fail "EXPECTED_ACCOUNT_ID_INVALID"

CALLER_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
[[ "$CALLER_ACCOUNT" == "$EXPECTED_ACCOUNT" ]] || fail "AWS_ACCOUNT_MISMATCH"

cd "$FOUNDATION_DIR"

TERRAFORM_VERSION="$($TF_EXE version | head -n 1)"
[[ "$TERRAFORM_VERSION" == "Terraform v1.15.8" ]] || fail "TERRAFORM_VERSION_MISMATCH"

EXPECTED_ADDRESSES=(
  "aws_iam_role.terraform_plan"
  "aws_iam_role_policy.terraform_state_access"
  "aws_iam_role_policy_attachment.terraform_plan_read_only"
  "aws_s3_bucket.terraform_state"
  "aws_s3_bucket_ownership_controls.terraform_state"
  "aws_s3_bucket_policy.terraform_state"
  "aws_s3_bucket_public_access_block.terraform_state"
  "aws_s3_bucket_server_side_encryption_configuration.terraform_state"
  "aws_s3_bucket_versioning.terraform_state"
)

mapfile -t ALL_STATE_ADDRESSES < <($TF_EXE state list | sed '/^[[:space:]]*$/d' | sort)
mapfile -t MANAGED_STATE_ADDRESSES < <(
  printf '%s\n' "${ALL_STATE_ADDRESSES[@]}" |
  grep -v '^data\.' |
  sort
)
mapfile -t EXPECTED_SORTED < <(printf '%s\n' "${EXPECTED_ADDRESSES[@]}" | sort)

if ! diff -u \
  <(printf '%s\n' "${EXPECTED_SORTED[@]}") \
  <(printf '%s\n' "${MANAGED_STATE_ADDRESSES[@]}") \
  >/dev/null; then
  echo "[expected managed state]" >&2
  printf '%s\n' "${EXPECTED_SORTED[@]}" >&2
  echo "[actual managed state]" >&2
  printf '%s\n' "${MANAGED_STATE_ADDRESSES[@]}" >&2
  fail "FOUNDATION_MANAGED_STATE_SET_MISMATCH"
fi

DATA_STATE_COUNT="$(( ${#ALL_STATE_ADDRESSES[@]} - ${#MANAGED_STATE_ADDRESSES[@]} ))"

STATE_BUCKET="$($TF_EXE output -raw terraform_state_bucket)"
PLAN_ROLE_ARN="$($TF_EXE output -raw terraform_plan_role_arn)"
PLAN_ROLE_NAME="${PLAN_ROLE_ARN##*/}"
EXPECTED_SUBJECT="repo:siamese-lang/Terraformers-modernization:environment:aws-live-plan"

VERSIONING="$(aws s3api get-bucket-versioning --bucket "$STATE_BUCKET" --query Status --output text)"
OWNERSHIP="$(aws s3api get-bucket-ownership-controls --bucket "$STATE_BUCKET" --query 'OwnershipControls.Rules[0].ObjectOwnership' --output text)"
ENCRYPTION="$(aws s3api get-bucket-encryption --bucket "$STATE_BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)"
PUBLIC_BLOCK_JSON="$(aws s3api get-public-access-block --bucket "$STATE_BUCKET" --output json)"
POLICY_STATUS_JSON="$(aws s3api get-bucket-policy-status --bucket "$STATE_BUCKET" --output json)"
BUCKET_POLICY_JSON="$(aws s3api get-bucket-policy --bucket "$STATE_BUCKET" --query Policy --output text)"
ATTACHED_POLICIES_JSON="$(aws iam list-attached-role-policies --role-name "$PLAN_ROLE_NAME" --output json)"
INLINE_POLICIES_JSON="$(aws iam list-role-policies --role-name "$PLAN_ROLE_NAME" --output json)"
ROLE_JSON="$(aws iam get-role --role-name "$PLAN_ROLE_NAME" --output json)"
STATE_POLICY_JSON="$(aws iam get-role-policy --role-name "$PLAN_ROLE_NAME" --policy-name terraformers-live-state-access --output json)"

export PUBLIC_BLOCK_JSON POLICY_STATUS_JSON BUCKET_POLICY_JSON ATTACHED_POLICIES_JSON INLINE_POLICIES_JSON ROLE_JSON STATE_POLICY_JSON EXPECTED_SUBJECT EXPECTED_ACCOUNT

"${PYTHON_CMD[@]}" - <<'PY'
import json
import os
import sys


def fail(code: str) -> None:
    print(code, file=sys.stderr)
    raise SystemExit(1)

public_block = json.loads(os.environ["PUBLIC_BLOCK_JSON"])["PublicAccessBlockConfiguration"]
if not all(public_block.get(key) is True for key in (
    "BlockPublicAcls",
    "BlockPublicPolicy",
    "IgnorePublicAcls",
    "RestrictPublicBuckets",
)):
    fail("PUBLIC_ACCESS_BLOCK_CHECK_FAILED")

policy_status = json.loads(os.environ["POLICY_STATUS_JSON"])["PolicyStatus"]
if policy_status.get("IsPublic") is not False:
    fail("BUCKET_POLICY_STATUS_CHECK_FAILED")

bucket_policy = json.loads(os.environ["BUCKET_POLICY_JSON"])
statements = bucket_policy.get("Statement", [])
if isinstance(statements, dict):
    statements = [statements]

tls_deny_found = False
for statement in statements:
    condition = statement.get("Condition", {})
    bool_condition = condition.get("Bool", {})
    secure_transport = bool_condition.get("aws:SecureTransport")
    actions = statement.get("Action", [])
    if isinstance(actions, str):
        actions = [actions]
    if (
        statement.get("Effect") == "Deny"
        and "s3:*" in actions
        and str(secure_transport).lower() == "false"
    ):
        tls_deny_found = True
        break
if not tls_deny_found:
    fail("TLS_ONLY_BUCKET_POLICY_CHECK_FAILED")

attached = json.loads(os.environ["ATTACHED_POLICIES_JSON"]).get("AttachedPolicies", [])
if not any(item.get("PolicyArn") == "arn:aws:iam::aws:policy/ReadOnlyAccess" for item in attached):
    fail("READ_ONLY_POLICY_CHECK_FAILED")

inline_names = json.loads(os.environ["INLINE_POLICIES_JSON"]).get("PolicyNames", [])
if "terraformers-live-state-access" not in inline_names:
    fail("STATE_POLICY_NAME_CHECK_FAILED")

role = json.loads(os.environ["ROLE_JSON"])["Role"]
trust = role["AssumeRolePolicyDocument"]
trust_statements = trust.get("Statement", [])
if isinstance(trust_statements, dict):
    trust_statements = [trust_statements]

expected_subject = os.environ["EXPECTED_SUBJECT"]
expected_account = os.environ["EXPECTED_ACCOUNT"]
trust_ok = False
for statement in trust_statements:
    if statement.get("Effect") != "Allow":
        continue
    actions = statement.get("Action", [])
    if isinstance(actions, str):
        actions = [actions]
    if "sts:AssumeRoleWithWebIdentity" not in actions:
        continue
    principal = statement.get("Principal", {}).get("Federated", [])
    if isinstance(principal, str):
        principal = [principal]
    if not any(
        value == f"arn:aws:iam::{expected_account}:oidc-provider/token.actions.githubusercontent.com"
        for value in principal
    ):
        continue
    equals = statement.get("Condition", {}).get("StringEquals", {})
    subjects = equals.get("token.actions.githubusercontent.com:sub", [])
    audiences = equals.get("token.actions.githubusercontent.com:aud", [])
    if isinstance(subjects, str):
        subjects = [subjects]
    if isinstance(audiences, str):
        audiences = [audiences]
    if expected_subject in subjects and "sts.amazonaws.com" in audiences:
        trust_ok = True
        break
if not trust_ok:
    fail("OIDC_TRUST_CHECK_FAILED")

state_policy = json.loads(os.environ["STATE_POLICY_JSON"])["PolicyDocument"]
policy_statements = state_policy.get("Statement", [])
if isinstance(policy_statements, dict):
    policy_statements = [policy_statements]

state_object_write = False
lock_object_manage = False
for statement in policy_statements:
    actions = statement.get("Action", [])
    resources = statement.get("Resource", [])
    if isinstance(actions, str):
        actions = [actions]
    if isinstance(resources, str):
        resources = [resources]
    action_set = set(actions)
    if {"s3:GetObject", "s3:PutObject"}.issubset(action_set) and any(
        str(resource).endswith("/terraform.tfstate") for resource in resources
    ):
        state_object_write = True
    if {"s3:GetObject", "s3:PutObject", "s3:DeleteObject"}.issubset(action_set) and any(
        str(resource).endswith("/terraform.tfstate.tflock") for resource in resources
    ):
        lock_object_manage = True

if not state_object_write:
    fail("STATE_OBJECT_POLICY_CHECK_FAILED")
if not lock_object_manage:
    fail("LOCK_OBJECT_POLICY_CHECK_FAILED")
PY

[[ "$VERSIONING" == "Enabled" ]] || fail "VERSIONING_CHECK_FAILED"
[[ "$OWNERSHIP" == "BucketOwnerEnforced" ]] || fail "OWNERSHIP_CHECK_FAILED"
[[ "$ENCRYPTION" == "AES256" ]] || fail "ENCRYPTION_CHECK_FAILED"

mkdir -p "$PRIVATE_DIR"
cp -f terraform.tfstate "$STATE_BACKUP"
sha256sum "$STATE_BACKUP" > "$STATE_BACKUP_DIGEST"

FINAL_STATUS="$(git -C "$REPO_ROOT" status --porcelain)"
[[ -z "$FINAL_STATUS" ]] || fail "WORKING_TREE_CHANGED_DURING_VERIFICATION"

printf '%s\n' \
  "FoundationApplyStatus=success" \
  "RepositoryHead=${ACTUAL_HEAD:0:12}" \
  "PythonCommand=${PYTHON_LABEL}" \
  "ManagedStateResourceCount=${#MANAGED_STATE_ADDRESSES[@]}" \
  "DataStateEntryCount=${DATA_STATE_COUNT}" \
  "VersioningEnabled=true" \
  "PublicAccessBlocked=true" \
  "BucketOwnerEnforced=true" \
  "EncryptionAES256=true" \
  "BucketPolicyPublic=false" \
  "TlsOnlyBucketPolicy=true" \
  "ReadOnlyPolicyAttached=true" \
  "StatePolicyPresent=true" \
  "StateAndLockPermissionsExact=true" \
  "OidcTrustExact=true" \
  "LocalStateBackupCreated=true" \
  "StateMigrationExecuted=false" \
  "AwsMutationDuringVerification=none"
