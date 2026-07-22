#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy/plan-live-foundation.sh \
    --tfvars PATH \
    [--terraform PATH] \
    [--plan PATH] \
    [--oidc-mode reuse|create] \
    [--expected-branch BRANCH] \
    [--expected-head SHA]

This command performs init, fmt, validate, plan, and plan review only.
It never runs terraform apply or terraform destroy.
EOF
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

normalize_existing_path() {
  local raw="$1"
  local unix_path

  if [[ -e "$raw" ]]; then
    unix_path="$raw"
  else
    unix_path="$(cygpath -u "$raw")"
  fi

  [[ -e "$unix_path" ]] || return 1
  (
    cd "$(dirname "$unix_path")"
    printf '%s/%s\n' "$(pwd -P)" "$(basename "$unix_path")"
  )
}

normalize_output_path() {
  local raw="$1"
  local unix_path

  if [[ "$raw" =~ ^[A-Za-z]:[\\/] ]]; then
    unix_path="$(cygpath -u "$raw")"
  else
    unix_path="$raw"
  fi

  mkdir -p "$(dirname "$unix_path")"
  (
    cd "$(dirname "$unix_path")"
    printf '%s/%s\n' "$(pwd -P)" "$(basename "$unix_path")"
  )
}

TFVARS_PATH=""
TERRAFORM_EXE=""
PLAN_PATH=""
OIDC_MODE="reuse"
EXPECTED_BRANCH="agent/rdb-domain-realignment"
EXPECTED_HEAD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tfvars)
      [[ $# -ge 2 ]] || fail "MISSING_TFVARS_VALUE"
      TFVARS_PATH="$2"
      shift 2
      ;;
    --terraform)
      [[ $# -ge 2 ]] || fail "MISSING_TERRAFORM_VALUE"
      TERRAFORM_EXE="$2"
      shift 2
      ;;
    --plan)
      [[ $# -ge 2 ]] || fail "MISSING_PLAN_VALUE"
      PLAN_PATH="$2"
      shift 2
      ;;
    --oidc-mode)
      [[ $# -ge 2 ]] || fail "MISSING_OIDC_MODE_VALUE"
      OIDC_MODE="$2"
      shift 2
      ;;
    --expected-branch)
      [[ $# -ge 2 ]] || fail "MISSING_EXPECTED_BRANCH_VALUE"
      EXPECTED_BRANCH="$2"
      shift 2
      ;;
    --expected-head)
      [[ $# -ge 2 ]] || fail "MISSING_EXPECTED_HEAD_VALUE"
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

[[ -n "$TFVARS_PATH" ]] || {
  usage >&2
  fail "TFVARS_PATH_REQUIRED"
}

[[ "$OIDC_MODE" == "reuse" || "$OIDC_MODE" == "create" ]] || fail "INVALID_OIDC_MODE"
command -v cygpath >/dev/null 2>&1 || fail "CYGPATH_NOT_FOUND_USE_GIT_BASH"
command -v git >/dev/null 2>&1 || fail "GIT_NOT_FOUND"
command -v python >/dev/null 2>&1 || fail "PYTHON_NOT_FOUND"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
FOUNDATION_DIR="$REPO_ROOT/infra/terraform/bootstrap/aws-live-foundation"
LOCK_FILE="$FOUNDATION_DIR/.terraform.lock.hcl"

LOCALAPPDATA_UNIX="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")"

if [[ -z "$TERRAFORM_EXE" ]]; then
  TERRAFORM_EXE="$LOCALAPPDATA_UNIX/Programs/Terraform/1.15.8/terraform.exe"
fi

if [[ -z "$PLAN_PATH" ]]; then
  PLAN_PATH="$LOCALAPPDATA_UNIX/Terraformers/live-foundation/foundation.tfplan"
fi

TFVARS_PATH_UNIX="$(normalize_existing_path "$TFVARS_PATH")" || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
TERRAFORM_EXE_UNIX="$(normalize_existing_path "$TERRAFORM_EXE")" || fail "TERRAFORM_1_15_8_NOT_FOUND"
PLAN_PATH_UNIX="$(normalize_output_path "$PLAN_PATH")"

TFVARS_PATH_WIN="$(cygpath -aw "$TFVARS_PATH_UNIX")"
PLAN_PATH_WIN="$(cygpath -aw "$PLAN_PATH_UNIX")"

REPO_ROOT_LOWER="${REPO_ROOT,,}"
TFVARS_PATH_LOWER="${TFVARS_PATH_UNIX,,}"
PLAN_PATH_LOWER="${PLAN_PATH_UNIX,,}"

case "$TFVARS_PATH_LOWER" in
  "$REPO_ROOT_LOWER"/*) fail "PRIVATE_TFVARS_MUST_BE_OUTSIDE_REPOSITORY" ;;
esac

case "$PLAN_PATH_LOWER" in
  "$REPO_ROOT_LOWER"/*) fail "BINARY_PLAN_MUST_BE_OUTSIDE_REPOSITORY" ;;
esac

if grep -Eq 'replace-|<12-digit|000000000000|state_bucket_name[[:space:]]*=[[:space:]]*""' "$TFVARS_PATH_UNIX"; then
  fail "PRIVATE_TFVARS_CONTAINS_PLACEHOLDER"
fi

cd "$REPO_ROOT"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}

CURRENT_BRANCH="$(git branch --show-current)"
[[ -z "$EXPECTED_BRANCH" || "$CURRENT_BRANCH" == "$EXPECTED_BRANCH" ]] || fail "BRANCH_MISMATCH"

CURRENT_HEAD="$(git rev-parse HEAD)"
[[ -z "$EXPECTED_HEAD" || "$CURRENT_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $CURRENT_HEAD"

TERRAFORM_VERSION_LINE="$("$TERRAFORM_EXE_UNIX" version | sed -n '1p')"
[[ "$TERRAFORM_VERSION_LINE" == "Terraform v1.15.8" ]] || fail "TERRAFORM_VERSION_MISMATCH: $TERRAFORM_VERSION_LINE"

[[ -f "$LOCK_FILE" ]] || fail "TERRAFORM_LOCK_FILE_NOT_FOUND"
grep -Fq 'version     = "5.100.0"' "$LOCK_FILE" || fail "AWS_PROVIDER_LOCK_MISMATCH"
grep -Fq 'version     = "4.3.0"' "$LOCK_FILE" || fail "TLS_PROVIDER_LOCK_MISMATCH"

export TF_IN_AUTOMATION=1
cd "$FOUNDATION_DIR"

"$TERRAFORM_EXE_UNIX" init -backend=false -input=false -lockfile=readonly
"$TERRAFORM_EXE_UNIX" fmt -check -diff
"$TERRAFORM_EXE_UNIX" validate

rm -f "$PLAN_PATH_UNIX"

set +e
PLAN_OUTPUT="$(
  "$TERRAFORM_EXE_UNIX" plan \
    -input=false \
    -lock=false \
    "-var-file=$TFVARS_PATH_WIN" \
    "-out=$PLAN_PATH_WIN" \
    -no-color 2>&1
)"
PLAN_EXIT_CODE=$?
set -e

if [[ $PLAN_EXIT_CODE -ne 0 ]]; then
  printf '%s\n' "$PLAN_OUTPUT" | tail -n 80 >&2
  fail "FOUNDATION_PLAN_FAILED"
fi

[[ -f "$PLAN_PATH_UNIX" ]] || fail "FOUNDATION_PLAN_NOT_CREATED"

read -r -d '' PYTHON_CODE <<'PY' || true
import json
import re
import sys

mode = sys.argv[1]
current_head = sys.argv[2]
plan = json.load(sys.stdin)

changes = []
for change in plan.get("resource_changes", []):
    if str(change.get("mode")) != "managed":
        continue
    changes.append(
        {
            "address": str(change.get("address", "")),
            "type": str(change.get("type", "")),
            "actions": list(change.get("change", {}).get("actions", [])),
            "raw": change,
        }
    )

expected = {
    "aws_iam_role.terraform_plan",
    "aws_iam_role_policy.terraform_state_access",
    "aws_iam_role_policy_attachment.terraform_plan_read_only",
    "aws_s3_bucket.terraform_state",
    "aws_s3_bucket_ownership_controls.terraform_state",
    "aws_s3_bucket_policy.terraform_state",
    "aws_s3_bucket_public_access_block.terraform_state",
    "aws_s3_bucket_server_side_encryption_configuration.terraform_state",
    "aws_s3_bucket_versioning.terraform_state",
}
if mode == "create":
    expected.add("aws_iam_openid_connect_provider.github_actions[0]")

actual = {item["address"] for item in changes}
if actual != expected:
    print("FOUNDATION_RESOURCE_SET_MISMATCH", file=sys.stderr)
    for value in sorted(expected - actual):
        print(f"missing: {value}", file=sys.stderr)
    for value in sorted(actual - expected):
        print(f"unexpected: {value}", file=sys.stderr)
    raise SystemExit(1)

for item in changes:
    actions = item["actions"]
    if "delete" in actions or "update" in actions:
        print(f"DANGEROUS_FOUNDATION_CHANGE_FOUND: {item['address']} {actions}", file=sys.stderr)
        raise SystemExit(1)
    if actions != ["create"]:
        print(f"NON_CREATE_FOUNDATION_ACTION_FOUND: {item['address']} {actions}", file=sys.stderr)
        raise SystemExit(1)

by_address = {item["address"]: item["raw"] for item in changes}
role = by_address["aws_iam_role.terraform_plan"]["change"]["after"]
attachment = by_address["aws_iam_role_policy_attachment.terraform_plan_read_only"]["change"]["after"]
bucket = by_address["aws_s3_bucket.terraform_state"]["change"]["after"]
public_access = by_address["aws_s3_bucket_public_access_block.terraform_state"]["change"]["after"]
versioning = by_address["aws_s3_bucket_versioning.terraform_state"]["change"]["after"]
encryption = by_address["aws_s3_bucket_server_side_encryption_configuration.terraform_state"]["change"]["after"]

variables = plan.get("variables", {})
account_id = str(variables.get("expected_aws_account_id", {}).get("value", ""))
region = str(variables.get("aws_region", {}).get("value", ""))
state_prefix = str(variables.get("state_prefix", {}).get("value", ""))
expected_bucket = f"terraformers-modernization-{account_id}-apne2-state"
expected_subject = "repo:siamese-lang/Terraformers-modernization:environment:aws-live-plan"
assume_policy = str(role.get("assume_role_policy", ""))

encryption_algorithm = str(
    encryption.get("rule", [{}])[0]
    .get("apply_server_side_encryption_by_default", [{}])[0]
    .get("sse_algorithm", "")
)
versioning_status = str(
    versioning.get("versioning_configuration", [{}])[0].get("status", "")
)

checks = {
    "ExpectedAccountIdValid": bool(re.fullmatch(r"[0-9]{12}", account_id)),
    "AwsRegionExact": region == "ap-northeast-2",
    "StatePrefixExact": state_prefix == "terraformers-modernization/dev",
    "StateBucketNameExact": str(bucket.get("bucket", "")) == expected_bucket,
    "OidcSubjectExact": expected_subject in assume_policy,
    "OidcAudienceExact": "sts.amazonaws.com" in assume_policy,
    "OidcProviderExact": "oidc-provider/token.actions.githubusercontent.com" in assume_policy,
    "ReadOnlyPolicyExact": str(attachment.get("policy_arn", "")) == "arn:aws:iam::aws:policy/ReadOnlyAccess",
    "ForceDestroyDisabled": bucket.get("force_destroy") is False,
    "PublicAccessBlocked": all(
        public_access.get(key) is True
        for key in (
            "block_public_acls",
            "block_public_policy",
            "ignore_public_acls",
            "restrict_public_buckets",
        )
    ),
    "VersioningEnabled": versioning_status == "Enabled",
    "EncryptionEnabled": encryption_algorithm == "AES256",
}

failed = [key for key, value in checks.items() if value is not True]
if failed:
    print("FOUNDATION_SECURITY_CHECK_FAILED", file=sys.stderr)
    for key in failed:
        print(f"{key}=False", file=sys.stderr)
    raise SystemExit(1)

rows = sorted(
    (
        item["address"],
        item["type"],
        ",".join(item["actions"]),
    )
    for item in changes
)
address_width = max(len("Address"), *(len(row[0]) for row in rows))
type_width = max(len("Type"), *(len(row[1]) for row in rows))

print("\n[foundation managed resource changes]")
print(f"{'Address':<{address_width}}  {'Type':<{type_width}}  Actions")
print(f"{'-' * address_width}  {'-' * type_width}  -------")
for address, resource_type, actions in rows:
    print(f"{address:<{address_width}}  {resource_type:<{type_width}}  {actions}")

summary = {
    "FoundationPlanStatus": "apply-review-ready",
    "RepositoryHead": current_head[:12],
    "TerraformVersion": "1.15.8",
    "AwsProviderVersion": "5.100.0",
    "TlsProviderVersion": "4.3.0",
    "CreateCount": len(changes),
    "ExpectedCreateCount": len(expected),
    "OidcProviderMode": mode,
    **checks,
    "DeleteCount": 0,
    "TerraformApplyExecuted": False,
    "AwsResourceMutation": "none",
    "PrivateTfvarsUploaded": False,
    "RawPlanUploaded": False,
}

print()
for key, value in summary.items():
    print(f"{key:<26}: {value}")
PY

"$TERRAFORM_EXE_UNIX" show -json "$PLAN_PATH_WIN" | python -c "$PYTHON_CODE" "$OIDC_MODE" "$CURRENT_HEAD"

cd "$REPO_ROOT"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_CHANGED_DURING_PLAN"
}
