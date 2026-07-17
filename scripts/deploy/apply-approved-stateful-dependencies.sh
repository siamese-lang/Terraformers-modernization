#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/deploy/apply-approved-stateful-dependencies.sh \
    --expected-head CURRENT_SHA \
    --approved-plan-head PLAN_SHA

Rebuild the stateful-dependencies plan with local AWS credentials, require the
exact reviewed five-resource create set, apply that saved plan once, and verify
RDS, Cognito, remote state, and a no-change post-apply plan. The command never
runs terraform destroy and never reads or prints a database secret value.
EOF
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

python_is_usable() {
  local output
  output="$("$@" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)" || return 1
  [[ "$output" =~ ^3\.[0-9]+$ ]]
}

read_tfvar_string() {
  local name="$1"
  sed -nE \
    "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" \
    "$FOUNDATION_TFVARS" |
    head -n 1
}

EXPECTED_HEAD=""
APPROVED_PLAN_HEAD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-head)
      [[ $# -ge 2 ]] || fail "EXPECTED_HEAD_VALUE_MISSING"
      EXPECTED_HEAD="$2"
      shift 2
      ;;
    --approved-plan-head)
      [[ $# -ge 2 ]] || fail "APPROVED_PLAN_HEAD_VALUE_MISSING"
      APPROVED_PLAN_HEAD="$2"
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

[[ "$EXPECTED_HEAD" =~ ^[0-9a-f]{40}$ ]] || fail "EXPECTED_HEAD_INVALID"
[[ "$APPROVED_PLAN_HEAD" =~ ^[0-9a-f]{40}$ ]] || fail "APPROVED_PLAN_HEAD_INVALID"

for command_name in git aws cygpath sed grep head rm mkdir cp sha256sum sleep; do
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

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
BRANCH="agent/rdb-domain-realignment"
STATEFUL_SOURCE="$REPO_ROOT/infra/terraform/envs/backend-stateful-dependencies"
SUMMARIZER="$REPO_ROOT/scripts/deploy/summarize-terraform-plan.py"
PRIVATE_DIR="$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA_NOT_SET}")/Terraformers/live-foundation"
FOUNDATION_TFVARS="$PRIVATE_DIR/foundation.tfvars"
FOUNDATION_STATE="$PRIVATE_DIR/foundation.remote-post-migration.tfstate"
STATEFUL_TFVARS="$PRIVATE_DIR/stateful-dependencies.live.tfvars"
APPROVED_SHORT="${APPROVED_PLAN_HEAD:0:12}"
APPROVED_REVIEW_DIR="$PRIVATE_DIR/stateful-dependencies-plan-review-${APPROVED_SHORT}"
APPROVED_RISK_MD="$APPROVED_REVIEW_DIR/plan-risk-summary.md"
TF_EXE="$(cygpath -u "$LOCALAPPDATA")/Programs/Terraform/1.15.8/terraform.exe"
WORK_DIR="$PRIVATE_DIR/stateful-dependencies-apply-${EXPECTED_HEAD:0:12}"
TF_DATA_DIR_UNIX="$WORK_DIR/tfdata"
TF_CLI_CONFIG="$WORK_DIR/terraform.tfrc"
BACKEND_CONFIG="$WORK_DIR/backend.hcl"
PLAN_PATH="$WORK_DIR/stateful-dependencies.tfplan"
PLAN_JSON="$WORK_DIR/stateful-dependencies-plan.json"
PLAN_LOG="$WORK_DIR/stateful-dependencies-plan.log"
APPLY_LOG="$WORK_DIR/stateful-dependencies-apply.log"
POST_PLAN_PATH="$WORK_DIR/stateful-dependencies-post-apply.tfplan"
POST_PLAN_LOG="$WORK_DIR/stateful-dependencies-post-apply-plan.log"
STATE_LIST="$WORK_DIR/stateful-dependencies-state-list.txt"
OUTPUTS_JSON="$WORK_DIR/stateful-dependencies-outputs.json"
RDS_JSON="$WORK_DIR/rds-verification.json"
SG_JSON="$WORK_DIR/database-security-group-verification.json"
COGNITO_POOL_JSON="$WORK_DIR/cognito-user-pool-verification.json"
COGNITO_CLIENT_JSON="$WORK_DIR/cognito-user-pool-client-verification.json"
RISK_DIR="$WORK_DIR/risk"
SUMMARY_PATH="$WORK_DIR/stateful-dependencies-apply-summary.txt"

[[ -x "$TF_EXE" ]] || fail "TERRAFORM_1_15_8_NOT_FOUND"
[[ -f "$FOUNDATION_TFVARS" ]] || fail "PRIVATE_FOUNDATION_TFVARS_NOT_FOUND"
[[ -f "$FOUNDATION_STATE" ]] || fail "VERIFIED_FOUNDATION_STATE_NOT_FOUND"
[[ -f "$STATEFUL_TFVARS" ]] || fail "PRIVATE_STATEFUL_DEPENDENCIES_TFVARS_NOT_FOUND"
[[ -f "$SUMMARIZER" ]] || fail "PLAN_SUMMARIZER_NOT_FOUND"
[[ -f "$APPROVED_RISK_MD" ]] || fail "APPROVED_STATEFUL_DEPENDENCIES_PLAN_REVIEW_NOT_FOUND"

cd "$REPO_ROOT"
[[ "$(git branch --show-current)" == "$BRANCH" ]] || fail "UNEXPECTED_CURRENT_BRANCH"
[[ -z "$(git status --porcelain)" ]] || {
  git status --short
  fail "WORKING_TREE_NOT_CLEAN"
}
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"
git cat-file -e "${APPROVED_PLAN_HEAD}^{commit}" 2>/dev/null || fail "APPROVED_PLAN_COMMIT_NOT_FOUND"
if ! git diff --quiet "$APPROVED_PLAN_HEAD" "$ACTUAL_HEAD" -- infra/terraform/envs/backend-stateful-dependencies; then
  fail "STATEFUL_DEPENDENCIES_CONFIGURATION_CHANGED_SINCE_APPROVED_PLAN"
fi

aws sts get-caller-identity --output json >/dev/null 2>&1 || fail "AWS_IDENTITY_UNAVAILABLE"
EXPECTED_ACCOUNT_ID="$(read_tfvar_string expected_aws_account_id)"
CALLER_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "EXPECTED_ACCOUNT_ID_INVALID"
[[ "$CALLER_ACCOUNT_ID" == "$EXPECTED_ACCOUNT_ID" ]] || fail "AWS_ACCOUNT_MISMATCH"

if grep -Eq 'replace-|000000000000|0\.0\.0\.0/0|::/0' "$STATEFUL_TFVARS"; then
  fail "STATEFUL_TFVARS_PLACEHOLDER_OR_PUBLIC_CIDR_PRESENT"
fi
grep -Fq 'database_instance_class               = "db.t4g.micro"' "$STATEFUL_TFVARS" || fail "STATEFUL_RDS_INSTANCE_CLASS_DRIFT"
grep -Fq 'database_multi_az                     = false' "$STATEFUL_TFVARS" || fail "STATEFUL_RDS_MULTI_AZ_DRIFT"
grep -Fq 'database_storage_encrypted            = true' "$STATEFUL_TFVARS" || fail "STATEFUL_RDS_ENCRYPTION_DRIFT"
grep -Fq 'database_publicly_accessible          = false' "$STATEFUL_TFVARS" || fail "STATEFUL_RDS_PUBLIC_ACCESS_DRIFT"
grep -Fq 'allowed_app_security_group_ids = []' "$STATEFUL_TFVARS" || fail "STATEFUL_APP_SECURITY_GROUP_BOUNDARY_DRIFT"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$TF_DATA_DIR_UNIX" "$RISK_DIR"
cp "$STATEFUL_SOURCE"/*.tf "$WORK_DIR/"
cat > "$WORK_DIR/backend.tf" <<'EOF'
terraform {
  backend "s3" {}
}
EOF
cat > "$TF_CLI_CONFIG" <<'EOF'
disable_checkpoint = true
EOF

"${PYTHON_CMD[@]}" - "$FOUNDATION_STATE" "$BACKEND_CONFIG" "$EXPECTED_ACCOUNT_ID" <<'PY'
import json
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
backend_path = Path(sys.argv[2])
expected_account = sys.argv[3]
state = json.loads(state_path.read_text(encoding="utf-8"))
outputs = state.get("outputs", {})

def value(name: str) -> str:
    entry = outputs.get(name)
    if not isinstance(entry, dict) or not isinstance(entry.get("value"), str):
        raise SystemExit(f"FOUNDATION_OUTPUT_INVALID: {name}")
    resolved = entry["value"].strip()
    if not resolved:
        raise SystemExit(f"FOUNDATION_OUTPUT_EMPTY: {name}")
    return resolved

account = value("aws_account_id")
region = value("aws_region")
bucket = value("terraform_state_bucket")
prefix = value("terraform_state_prefix").strip("/")
if account != expected_account:
    raise SystemExit("FOUNDATION_STATE_ACCOUNT_MISMATCH")
if region != "ap-northeast-2":
    raise SystemExit("FOUNDATION_STATE_REGION_MISMATCH")
backend_path.write_text(
    f'bucket       = "{bucket}"\n'
    f'key          = "{prefix}/stateful-dependencies/terraform.tfstate"\n'
    f'region       = "{region}"\n'
    'encrypt      = true\n'
    'use_lockfile = true\n',
    encoding="utf-8",
)
PY

TERRAFORM_VERSION="$($TF_EXE version | sed -n '1p')"
[[ "$TERRAFORM_VERSION" == "Terraform v1.15.8" ]] || fail "TERRAFORM_VERSION_MISMATCH: $TERRAFORM_VERSION"

BACKEND_CONFIG_WIN="$(cygpath -am "$BACKEND_CONFIG")"
STATEFUL_TFVARS_WIN="$(cygpath -am "$STATEFUL_TFVARS")"
PLAN_PATH_WIN="$(cygpath -am "$PLAN_PATH")"
POST_PLAN_PATH_WIN="$(cygpath -am "$POST_PLAN_PATH")"
TF_DATA_DIR_WIN="$(cygpath -am "$TF_DATA_DIR_UNIX")"
TF_CLI_CONFIG_WIN="$(cygpath -am "$TF_CLI_CONFIG")"
WORK_DIR_WIN="$(cygpath -am "$WORK_DIR")"

export TF_DATA_DIR="$TF_DATA_DIR_WIN"
export TF_CLI_CONFIG_FILE="$TF_CLI_CONFIG_WIN"
export TF_IN_AUTOMATION=1
export GOGC="${GOGC:-25}"
export AWS_RETRY_MODE="${AWS_RETRY_MODE:-standard}"
export AWS_MAX_ATTEMPTS="${AWS_MAX_ATTEMPTS:-10}"
unset TF_PLUGIN_CACHE_DIR || true

"$TF_EXE" -chdir="$WORK_DIR_WIN" init \
  -input=false \
  -reconfigure \
  -backend-config="$BACKEND_CONFIG_WIN"

set +e
"$TF_EXE" -chdir="$WORK_DIR_WIN" plan \
  -input=false \
  -lock-timeout=5m \
  -parallelism=1 \
  -var-file="$STATEFUL_TFVARS_WIN" \
  -out="$PLAN_PATH_WIN" \
  -no-color > "$PLAN_LOG" 2>&1
PLAN_EXIT_CODE=$?
set -e
[[ "$PLAN_EXIT_CODE" -eq 0 ]] || fail "STATEFUL_DEPENDENCIES_REPLAN_FAILED"

"$TF_EXE" -chdir="$WORK_DIR_WIN" show -json "$PLAN_PATH_WIN" > "$PLAN_JSON"
"${PYTHON_CMD[@]}" "$SUMMARIZER" \
  --plan-json "$PLAN_JSON" \
  --output-dir "$RISK_DIR" \
  --stage stateful-dependencies >/dev/null

"${PYTHON_CMD[@]}" - "$APPROVED_RISK_MD" "$PLAN_JSON" <<'PY'
import json
import re
import sys
from pathlib import Path

approved_md = Path(sys.argv[1]).read_text(encoding="utf-8")
plan = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
row_pattern = re.compile(r'^\| `([^`]+)` \| `([^`]+)` \| `([^`]+)` \|$', re.MULTILINE)
approved = {
    (address, resource_type, tuple(action for action in actions.split(",") if action))
    for address, resource_type, actions in row_pattern.findall(approved_md)
}
actual = {
    (
        str(change.get("address", "")),
        str(change.get("type", "")),
        tuple(change.get("change", {}).get("actions", [])),
    )
    for change in plan.get("resource_changes", [])
}
expected_types = {
    "aws_security_group.backend_database": "aws_security_group",
    "aws_db_subnet_group.backend": "aws_db_subnet_group",
    "aws_db_instance.backend": "aws_db_instance",
    "aws_cognito_user_pool.backend": "aws_cognito_user_pool",
    "aws_cognito_user_pool_client.backend": "aws_cognito_user_pool_client",
}
expected = {(address, resource_type, ("create",)) for address, resource_type in expected_types.items()}
if approved != actual:
    raise SystemExit("REPLAN_RESOURCE_ACTION_MISMATCH")
if actual != expected:
    raise SystemExit("REPLAN_EXPECTED_RESOURCE_SET_MISMATCH")
if len(actual) != 5:
    raise SystemExit("REPLAN_RESOURCE_COUNT_MISMATCH")
print("ApprovedResourceActionMatch=true")
print("ApprovedResourceCount=5")
PY

grep -Fqx 'terraform_plan_risk_gate=passed' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_RISK_GATE_FAILED"
grep -Fqx 'resource_change_count=5' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_RESOURCE_COUNT_MISMATCH"
grep -Fqx 'destructive_resource_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_DESTRUCTIVE_CHANGE_PRESENT"
grep -Fqx 'replacement_resource_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_REPLACEMENT_PRESENT"
grep -Fqx 'public_exposure_finding_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_PUBLIC_EXPOSURE_PRESENT"
grep -Fqx 'optional_adapter_resource_count=0' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_OPTIONAL_ADAPTER_PRESENT"
grep -Fqx 'high_cost_resource_count=1' "$RISK_DIR/plan-risk-summary.txt" || fail "REPLAN_HIGH_COST_COUNT_MISMATCH"

sha256sum "$PLAN_PATH" > "$WORK_DIR/stateful-dependencies.tfplan.sha256"
printf '%s\n' \
  "StatefulDependenciesApplyStarted=true" \
  "ApprovedPlanHead=${APPROVED_SHORT}" \
  "ApprovedResourceActionMatch=true" \
  "ApprovedResourceCount=5" \
  "DatabasePubliclyAccessible=false" \
  "DatabaseMultiAz=false" \
  "DatabaseSecretValueReadExecuted=false" \
  "TerraformDestroyExecuted=false"

set +e
"$TF_EXE" -chdir="$WORK_DIR_WIN" apply \
  -input=false \
  -parallelism=1 \
  -no-color \
  "$PLAN_PATH_WIN" > "$APPLY_LOG" 2>&1
APPLY_EXIT_CODE=$?
set -e
if [[ "$APPLY_EXIT_CODE" -ne 0 ]]; then
  printf '%s\n' \
    "StatefulDependenciesApplyStatus=failed-or-partial" \
    "DoNotRerunAutomatically=true" \
    "DatabaseSecretValueReadExecuted=false" \
    "TerraformDestroyExecuted=false" \
    "PrivateApplyLogCreated=true" >&2
  exit "$APPLY_EXIT_CODE"
fi

"$TF_EXE" -chdir="$WORK_DIR_WIN" state list > "$STATE_LIST"
MANAGED_STATE_COUNT="$(grep -v '^data\.' "$STATE_LIST" | grep -c . || true)"
[[ "$MANAGED_STATE_COUNT" == "5" ]] || fail "STATEFUL_DEPENDENCIES_MANAGED_STATE_COUNT_MISMATCH"
for address in \
  aws_cognito_user_pool.backend \
  aws_cognito_user_pool_client.backend \
  aws_db_instance.backend \
  aws_db_subnet_group.backend \
  aws_security_group.backend_database; do
  grep -Fqx "$address" "$STATE_LIST" || fail "STATEFUL_DEPENDENCIES_STATE_ADDRESS_MISSING"
done

"$TF_EXE" -chdir="$WORK_DIR_WIN" output -json > "$OUTPUTS_JSON"
"${PYTHON_CMD[@]}" - "$OUTPUTS_JSON" <<'PY'
import json
import sys
from pathlib import Path

outputs = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
required_strings = (
    "database_security_group_id",
    "database_subnet_group_name",
    "database_instance_id",
    "database_instance_arn",
    "database_endpoint",
    "database_name",
    "database_username",
    "database_master_user_secret_arn",
    "spring_datasource_url",
    "cognito_region",
    "cognito_user_pool_id",
    "cognito_user_pool_client_id",
    "cognito_jwks_url",
)
for name in required_strings:
    value = outputs.get(name, {}).get("value")
    if not isinstance(value, str) or not value:
        raise SystemExit(f"STATEFUL_DEPENDENCIES_OUTPUT_INVALID: {name}")
if outputs.get("database_port", {}).get("value") != 3306:
    raise SystemExit("STATEFUL_DATABASE_PORT_OUTPUT_INVALID")
if outputs["database_name"]["value"] != "terraformers":
    raise SystemExit("STATEFUL_DATABASE_NAME_OUTPUT_INVALID")
if outputs["cognito_region"]["value"] != "ap-northeast-2":
    raise SystemExit("STATEFUL_COGNITO_REGION_OUTPUT_INVALID")
if not outputs["spring_datasource_url"]["value"].startswith("jdbc:mariadb://"):
    raise SystemExit("STATEFUL_JDBC_URL_OUTPUT_INVALID")
if "/.well-known/jwks.json" not in outputs["cognito_jwks_url"]["value"]:
    raise SystemExit("STATEFUL_COGNITO_JWKS_OUTPUT_INVALID")
PY

DB_ID="$("${PYTHON_CMD[@]}" - "$OUTPUTS_JSON" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["database_instance_id"]["value"])
PY
)"
SG_ID="$("${PYTHON_CMD[@]}" - "$OUTPUTS_JSON" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["database_security_group_id"]["value"])
PY
)"
POOL_ID="$("${PYTHON_CMD[@]}" - "$OUTPUTS_JSON" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["cognito_user_pool_id"]["value"])
PY
)"
CLIENT_ID="$("${PYTHON_CMD[@]}" - "$OUTPUTS_JSON" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["cognito_user_pool_client_id"]["value"])
PY
)"
MASTER_SECRET_ARN="$("${PYTHON_CMD[@]}" - "$OUTPUTS_JSON" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["database_master_user_secret_arn"]["value"])
PY
)"
[[ -n "$DB_ID" && -n "$SG_ID" && -n "$POOL_ID" && -n "$CLIENT_ID" && -n "$MASTER_SECRET_ARN" ]] || fail "STATEFUL_VERIFICATION_IDENTIFIERS_MISSING"

aws rds describe-db-instances --db-instance-identifier "$DB_ID" --output json > "$RDS_JSON"
aws ec2 describe-security-groups --group-ids "$SG_ID" --output json > "$SG_JSON"
aws cognito-idp describe-user-pool --user-pool-id "$POOL_ID" --output json > "$COGNITO_POOL_JSON"
aws cognito-idp describe-user-pool-client --user-pool-id "$POOL_ID" --client-id "$CLIENT_ID" --output json > "$COGNITO_CLIENT_JSON"
aws secretsmanager describe-secret --secret-id "$MASTER_SECRET_ARN" >/dev/null 2>&1 || fail "RDS_MANAGED_MASTER_SECRET_CONTAINER_MISSING"

"${PYTHON_CMD[@]}" - "$RDS_JSON" "$SG_JSON" "$COGNITO_POOL_JSON" "$COGNITO_CLIENT_JSON" "$STATEFUL_TFVARS" <<'PY'
import json
import re
import sys
from pathlib import Path

rds = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["DBInstances"][0]
sg = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))["SecurityGroups"][0]
pool = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))["UserPool"]
client = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))["UserPoolClient"]
tfvars = Path(sys.argv[5]).read_text(encoding="utf-8")

expected_rds = {
    "DBInstanceStatus": "available",
    "Engine": "mariadb",
    "DBInstanceClass": "db.t4g.micro",
    "AllocatedStorage": 20,
    "StorageEncrypted": True,
    "PubliclyAccessible": False,
    "MultiAZ": False,
}
for key, expected in expected_rds.items():
    if rds.get(key) != expected:
        raise SystemExit(f"RDS_PROPERTY_MISMATCH: {key}")
if not isinstance(rds.get("MasterUserSecret", {}).get("SecretArn"), str):
    raise SystemExit("RDS_MANAGED_MASTER_SECRET_ARN_MISSING")

match = re.search(r'allowed_database_cidr_blocks\s*=\s*\[(.*?)\]', tfvars, re.DOTALL)
if not match:
    raise SystemExit("STATEFUL_ALLOWED_DATABASE_CIDRS_NOT_FOUND")
expected_cidrs = set(re.findall(r'"([0-9.]+/[0-9]+)"', match.group(1)))
if len(expected_cidrs) != 2 or "0.0.0.0/0" in expected_cidrs:
    raise SystemExit("STATEFUL_ALLOWED_DATABASE_CIDRS_INVALID")
actual_cidrs = set()
for permission in sg.get("IpPermissions", []):
    if permission.get("IpProtocol") != "tcp" or permission.get("FromPort") != 3306 or permission.get("ToPort") != 3306:
        raise SystemExit("DATABASE_SECURITY_GROUP_INGRESS_RULE_UNEXPECTED")
    if permission.get("Ipv6Ranges") or permission.get("UserIdGroupPairs") or permission.get("PrefixListIds"):
        raise SystemExit("DATABASE_SECURITY_GROUP_NON_CIDR_INGRESS_PRESENT")
    actual_cidrs.update(item.get("CidrIp") for item in permission.get("IpRanges", []))
if actual_cidrs != expected_cidrs:
    raise SystemExit("DATABASE_SECURITY_GROUP_CIDR_MISMATCH")

if pool.get("Name") != "terraformers-modernization-dev-users":
    raise SystemExit("COGNITO_USER_POOL_NAME_MISMATCH")
if pool.get("DeletionProtection") != "INACTIVE" or pool.get("MfaConfiguration") != "OFF":
    raise SystemExit("COGNITO_USER_POOL_PROTECTION_OR_MFA_MISMATCH")
if set(pool.get("UsernameAttributes", [])) != {"email"}:
    raise SystemExit("COGNITO_USERNAME_ATTRIBUTE_MISMATCH")
if set(pool.get("AutoVerifiedAttributes", [])) != {"email"}:
    raise SystemExit("COGNITO_AUTO_VERIFIED_ATTRIBUTE_MISMATCH")

if "ClientSecret" in client:
    raise SystemExit("COGNITO_CLIENT_SECRET_UNEXPECTED")
expected_flows = {"ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH"}
if set(client.get("ExplicitAuthFlows", [])) != expected_flows:
    raise SystemExit("COGNITO_CLIENT_AUTH_FLOW_MISMATCH")
if set(client.get("SupportedIdentityProviders", [])) != {"COGNITO"}:
    raise SystemExit("COGNITO_CLIENT_PROVIDER_MISMATCH")
if client.get("PreventUserExistenceErrors") != "ENABLED":
    raise SystemExit("COGNITO_CLIENT_USER_EXISTENCE_BOUNDARY_MISMATCH")
PY

sleep 5
set +e
"$TF_EXE" -chdir="$WORK_DIR_WIN" plan \
  -input=false \
  -lock-timeout=5m \
  -parallelism=1 \
  -detailed-exitcode \
  -var-file="$STATEFUL_TFVARS_WIN" \
  -out="$POST_PLAN_PATH_WIN" \
  -no-color > "$POST_PLAN_LOG" 2>&1
POST_PLAN_EXIT_CODE=$?
set -e
[[ "$POST_PLAN_EXIT_CODE" -eq 0 ]] || fail "POST_APPLY_PLAN_NOT_EMPTY"

STATE_BUCKET="$(sed -nE 's/^[[:space:]]*bucket[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$BACKEND_CONFIG" | head -n 1)"
STATE_KEY="$(sed -nE 's/^[[:space:]]*key[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$BACKEND_CONFIG" | head -n 1)"
[[ -n "$STATE_BUCKET" && -n "$STATE_KEY" ]] || fail "STATEFUL_DEPENDENCIES_BACKEND_VALUES_MISSING"
if aws s3api head-object --bucket "$STATE_BUCKET" --key "${STATE_KEY}.tflock" >/dev/null 2>&1; then
  fail "STALE_STATEFUL_DEPENDENCIES_LOCK_OBJECT_PRESENT"
fi
aws s3api head-object --bucket "$STATE_BUCKET" --key "$STATE_KEY" >/dev/null 2>&1 || fail "STATEFUL_DEPENDENCIES_REMOTE_STATE_OBJECT_MISSING"

rm -f "$PLAN_JSON" "$PLAN_PATH" "$POST_PLAN_PATH"

cat > "$SUMMARY_PATH" <<EOF
StatefulDependenciesApplyStatus=success
RepositoryHead=${ACTUAL_HEAD:0:12}
ApprovedPlanHead=${APPROVED_SHORT}
PythonCommand=${PYTHON_LABEL}
ProviderMemoryMode=GOGC-${GOGC}
ApprovedResourceActionMatch=true
CreatedResourceCount=5
ManagedStateResourceCount=5
DatabaseInstanceCount=1
DatabaseSubnetGroupCount=1
DatabaseSecurityGroupCount=1
CognitoUserPoolCount=1
CognitoUserPoolClientCount=1
DatabaseEngine=mariadb
DatabaseInstanceClass=db.t4g.micro
DatabaseAllocatedStorageGb=20
DatabaseStorageEncrypted=true
DatabasePubliclyAccessible=false
DatabaseMultiAz=false
DatabaseManagedMasterSecretPresent=true
DatabaseSecretValueReadExecuted=false
DatabaseIngressPrivateCidrsOnly=true
CognitoClientSecretGenerated=false
PostApplyPlanNoChanges=true
RemoteStateObjectPresent=true
StaleLockObjectPresent=false
TerraformApplyExecuted=true
TerraformDestroyExecuted=false
GitHubMutation=none
AwsMutation=stateful-dependencies-5-create
PrivateEvidenceDirectoryCreated=true
EOF
cat "$SUMMARY_PATH"
