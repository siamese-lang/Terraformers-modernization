#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/deploy/prepare-and-dispatch-backend-image-publish.sh \
    --expected-head CURRENT_SHA \
    --runtime-apply-head APPLIED_SHA \
    [--execute-publish]

Default mode is read-only preparation. It validates the task-local repository
HEAD, private runtime-dependencies apply evidence, GitHub OIDC publisher role
trust/policy, ECR repository scope, and prints the exact GitHub Environment and
workflow dispatch plan. It performs no Terraform, Docker, AWS, GitHub, or
Kubernetes mutation unless --execute-publish is explicitly provided.
USAGE
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
  local file="$1"
  local name="$2"
  sed -nE "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\\1/p" "$file" | head -n 1
}

EXPECTED_HEAD=""
RUNTIME_APPLY_HEAD=""
EXECUTE_PUBLISH=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-head)
      [[ $# -ge 2 ]] || fail "EXPECTED_HEAD_VALUE_MISSING"
      EXPECTED_HEAD="$2"
      shift 2
      ;;
    --runtime-apply-head)
      [[ $# -ge 2 ]] || fail "RUNTIME_APPLY_HEAD_VALUE_MISSING"
      RUNTIME_APPLY_HEAD="$2"
      shift 2
      ;;
    --execute-publish)
      EXECUTE_PUBLISH=true
      shift
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
[[ "$RUNTIME_APPLY_HEAD" =~ ^[0-9a-f]{40}$ ]] || fail "RUNTIME_APPLY_HEAD_INVALID"

for command_name in git sed head; do
  command -v "$command_name" >/dev/null 2>&1 || fail "REQUIRED_COMMAND_NOT_FOUND: $command_name"
done

PYTHON_CMD=()
if command -v py >/dev/null 2>&1 && python_is_usable py -3; then
  PYTHON_CMD=(py -3)
elif command -v python >/dev/null 2>&1 && python_is_usable python; then
  PYTHON_CMD=(python)
elif command -v python3 >/dev/null 2>&1 && python_is_usable python3; then
  PYTHON_CMD=(python3)
else
  fail "USABLE_PYTHON3_NOT_FOUND"
fi

REPO="siamese-lang/Terraformers-modernization"
SOURCE_BRANCH="agent/rdb-domain-realignment"
ENVIRONMENT="aws-backend-image-publish"
WORKFLOW="backend-image-publish.yml"
REPOSITORY_NAME="terraformers-backend"
EXPECTED_SUBJECT="repo:${REPO}:environment:${ENVIRONMENT}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "NOT_INSIDE_GIT_REPOSITORY"
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"
WORKFLOW_PATH="$REPO_ROOT/.github/workflows/$WORKFLOW"
FOUNDATION_TFVARS_FALLBACK=""
PRIVATE_ROOT=""
if command -v cygpath >/dev/null 2>&1 && [[ -n "${LOCALAPPDATA:-}" ]]; then
  PRIVATE_ROOT="$(cygpath -u "$LOCALAPPDATA")/Terraformers/live-foundation"
elif [[ -n "${LOCALAPPDATA:-}" ]]; then
  PRIVATE_ROOT="$LOCALAPPDATA/Terraformers/live-foundation"
else
  fail "LOCALAPPDATA_NOT_SET"
fi
FOUNDATION_TFVARS="$PRIVATE_ROOT/foundation.tfvars"
FOUNDATION_STATE="$PRIVATE_ROOT/foundation.remote-post-migration.tfstate"
RUNTIME_DIR="$PRIVATE_ROOT/runtime-dependencies-apply-${RUNTIME_APPLY_HEAD:0:12}"
SUMMARY_PATH="$RUNTIME_DIR/runtime-dependencies-apply-summary.txt"
OUTPUTS_JSON="$RUNTIME_DIR/runtime-dependencies-outputs.json"

cd "$REPO_ROOT"
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || fail "HEAD_MISMATCH: $ACTUAL_HEAD"
[[ -z "$(git status --porcelain)" ]] || { git status --short; fail "WORKING_TREE_NOT_CLEAN"; }
git cat-file -e "${RUNTIME_APPLY_HEAD}^{commit}" 2>/dev/null || fail "RUNTIME_APPLY_COMMIT_NOT_FOUND"
git merge-base --is-ancestor "$RUNTIME_APPLY_HEAD" "$EXPECTED_HEAD" || fail "RUNTIME_APPLY_NOT_ANCESTOR"
git diff --quiet "$RUNTIME_APPLY_HEAD" "$EXPECTED_HEAD" -- infra/terraform/envs/backend-runtime-dependencies || fail "RUNTIME_PUBLISHER_CONFIGURATION_CHANGED_SINCE_APPLY"

if command -v git >/dev/null 2>&1; then
  REMOTE_SOURCE_HEAD="$(git ls-remote origin "refs/heads/${SOURCE_BRANCH}" 2>/dev/null | awk '{print $1}' || true)"
  if [[ -n "$REMOTE_SOURCE_HEAD" && "$REMOTE_SOURCE_HEAD" != "$EXPECTED_HEAD" ]]; then
    fail "REMOTE_SOURCE_HEAD_MISMATCH"
  fi
fi

[[ -f "$SUMMARY_PATH" ]] || fail "RUNTIME_APPLY_EVIDENCE_NOT_FOUND: $SUMMARY_PATH"
[[ -f "$OUTPUTS_JSON" ]] || fail "RUNTIME_APPLY_EVIDENCE_NOT_FOUND: $OUTPUTS_JSON"
[[ -f "$WORKFLOW_PATH" ]] || fail "BACKEND_IMAGE_PUBLISH_WORKFLOW_NOT_FOUND"

for contract_line in \
  'RuntimeDependenciesApplyStatus=success' \
  "RepositoryHead=${RUNTIME_APPLY_HEAD:0:12}" \
  'ApprovedResourceActionMatch=true' \
  'CreatedResourceCount=3' \
  'ManagedStateResourceCount=16' \
  'PublisherIamRoleCount=1' \
  'PublisherIamPolicyCount=1' \
  'PublisherIamRolePolicyAttachmentCount=1' \
  'PostApplyPlanNoChanges=true' \
  'RemoteStateObjectPresent=true' \
  'StaleLockObjectPresent=false' \
  'TerraformApplyExecuted=true' \
  'TerraformDestroyExecuted=false'; do
  if ! grep -Fqx "$contract_line" "$SUMMARY_PATH"; then
    if [[ "$contract_line" == RepositoryHead=* ]]; then
      fail "RUNTIME_APPLY_SUMMARY_HEAD_MISMATCH"
    fi
    fail "RUNTIME_APPLY_CONTRACT_MISMATCH: $contract_line"
  fi
done

ACCOUNT_REGION_JSON="$RUNTIME_DIR/backend-image-publish-foundation-values.json"
"${PYTHON_CMD[@]}" - "$OUTPUTS_JSON" "$FOUNDATION_STATE" "$FOUNDATION_TFVARS" "$ACCOUNT_REGION_JSON" "$EXPECTED_HEAD" "$REPOSITORY_NAME" <<'PY'
import json
import re
import sys
from pathlib import Path

outputs_path, state_path, tfvars_path, values_path, expected_head, repository = map(Path, sys.argv[1:7])
outputs = json.loads(outputs_path.read_text(encoding="utf-8"))

def output_value(name: str) -> str:
    entry = outputs.get(name)
    if not isinstance(entry, dict) or not isinstance(entry.get("value"), str):
        raise SystemExit(f"RUNTIME_OUTPUT_INVALID: {name}")
    value = entry["value"].strip()
    if not value:
        raise SystemExit(f"RUNTIME_OUTPUT_EMPTY: {name}")
    return value

role_arn = output_value("backend_image_publisher_role_arn")
repo_url = output_value("backend_image_repository_url")
role_match = re.fullmatch(r"arn:aws[a-zA-Z-]*:iam::([0-9]{12}):role/.+", role_arn)
repo_match = re.fullmatch(r"([0-9]{12})\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com/([a-z0-9._/-]+)", repo_url)
if role_match is None:
    raise SystemExit("PUBLISHER_ROLE_ARN_INVALID")
if repo_match is None:
    raise SystemExit("BACKEND_IMAGE_REPOSITORY_URL_INVALID")
if repo_match.group(3) != str(repository):
    raise SystemExit("BACKEND_IMAGE_REPOSITORY_NAME_MISMATCH")
if role_match.group(1) != repo_match.group(1):
    raise SystemExit("PUBLISHER_ROLE_REPOSITORY_ACCOUNT_MISMATCH")

account = region = None
if state_path.is_file():
    state = json.loads(state_path.read_text(encoding="utf-8"))
    state_outputs = state.get("outputs", {})
    for key, target in (("aws_account_id", "account"), ("aws_region", "region")):
        entry = state_outputs.get(key)
        if isinstance(entry, dict) and isinstance(entry.get("value"), str):
            if target == "account": account = entry["value"].strip()
            else: region = entry["value"].strip()
if (not account or not region) and tfvars_path.is_file():
    text = tfvars_path.read_text(encoding="utf-8")
    def tfvar(name: str):
        match = re.search(rf'^\s*{re.escape(name)}\s*=\s*"([^"]+)"', text, re.M)
        return match.group(1).strip() if match else None
    account = account or tfvar("expected_aws_account_id") or tfvar("aws_account_id")
    region = region or tfvar("aws_region")
if not re.fullmatch(r"[0-9]{12}", account or ""):
    raise SystemExit("FOUNDATION_ACCOUNT_ID_UNAVAILABLE")
if not re.fullmatch(r"[a-z]{2}-[a-z]+-[0-9]", region or ""):
    raise SystemExit("FOUNDATION_REGION_UNAVAILABLE")
if account != role_match.group(1) or account != repo_match.group(1):
    raise SystemExit("FOUNDATION_ACCOUNT_OUTPUT_MISMATCH")
if region != repo_match.group(2):
    raise SystemExit("FOUNDATION_REGION_REPOSITORY_MISMATCH")
image_uri = f"{account}.dkr.ecr.{region}.amazonaws.com/{repository}:git-{expected_head}"
values_path.write_text(json.dumps({"role_arn": role_arn, "repository_url": repo_url, "account": account, "region": region, "image_uri": image_uri}, indent=2) + "\n", encoding="utf-8")
PY

ROLE_ARN="$(${PYTHON_CMD[@]} -c 'import json,sys; print(json.load(open(sys.argv[1]))["role_arn"])' "$ACCOUNT_REGION_JSON")"
REPOSITORY_URL="$(${PYTHON_CMD[@]} -c 'import json,sys; print(json.load(open(sys.argv[1]))["repository_url"])' "$ACCOUNT_REGION_JSON")"
AWS_REGION="$(${PYTHON_CMD[@]} -c 'import json,sys; print(json.load(open(sys.argv[1]))["region"])' "$ACCOUNT_REGION_JSON")"
EXPECTED_ACCOUNT_ID="$(${PYTHON_CMD[@]} -c 'import json,sys; print(json.load(open(sys.argv[1]))["account"])' "$ACCOUNT_REGION_JSON")"
IMAGE_URI="$(${PYTHON_CMD[@]} -c 'import json,sys; print(json.load(open(sys.argv[1]))["image_uri"])' "$ACCOUNT_REGION_JSON")"
rm -f "$ACCOUNT_REGION_JSON"

for command_name in aws; do
  command -v "$command_name" >/dev/null 2>&1 || fail "REQUIRED_COMMAND_NOT_FOUND: $command_name"
done
CALLER_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION")"
[[ "$CALLER_ACCOUNT_ID" == "$EXPECTED_ACCOUNT_ID" ]] || fail "AWS_ACCOUNT_MISMATCH"

TRUST_JSON="$(aws iam get-role --role-name "${ROLE_ARN##*/}" --query 'Role.AssumeRolePolicyDocument' --output json)"
POLICY_ARN="$(aws iam list-attached-role-policies --role-name "${ROLE_ARN##*/}" --query 'AttachedPolicies[?contains(PolicyName, `backend-image-publisher`)].PolicyArn | [0]' --output text)"
[[ "$POLICY_ARN" == arn:aws*:iam::"$EXPECTED_ACCOUNT_ID":policy/*backend-image-publisher* ]] || fail "PUBLISHER_POLICY_ATTACHMENT_NOT_FOUND"
POLICY_JSON="$(aws iam get-policy-version --policy-arn "$POLICY_ARN" --version-id "$(aws iam get-policy --policy-arn "$POLICY_ARN" --query 'Policy.DefaultVersionId' --output text)" --query 'PolicyVersion.Document' --output json)"
REPO_ARN="$(aws ecr describe-repositories --repository-names "$REPOSITORY_NAME" --region "$AWS_REGION" --query 'repositories[0].repositoryArn' --output text)"
ECR_REPO_URI="$(aws ecr describe-repositories --repository-names "$REPOSITORY_NAME" --region "$AWS_REGION" --query 'repositories[0].repositoryUri' --output text)"
[[ "$ECR_REPO_URI" == "$REPOSITORY_URL" ]] || fail "ECR_REPOSITORY_URI_MISMATCH"

"${PYTHON_CMD[@]}" - "$TRUST_JSON" "$POLICY_JSON" "$EXPECTED_SUBJECT" "$REPO_ARN" <<'PY'
import json
import sys
trust = json.loads(sys.argv[1])
policy = json.loads(sys.argv[2])
expected_subject = sys.argv[3]
repo_arn = sys.argv[4]
statements = trust.get("Statement", [])
if isinstance(statements, dict): statements = [statements]
if len(statements) != 1: raise SystemExit("PUBLISHER_TRUST_STATEMENT_COUNT_MISMATCH")
stmt = statements[0]
conditions = stmt.get("Condition", {}).get("StringEquals", {})
if stmt.get("Effect") != "Allow" or stmt.get("Action") != "sts:AssumeRoleWithWebIdentity": raise SystemExit("PUBLISHER_TRUST_ACTION_INVALID")
if conditions.get("token.actions.githubusercontent.com:aud") != "sts.amazonaws.com": raise SystemExit("PUBLISHER_TRUST_AUDIENCE_MISMATCH")
if conditions.get("token.actions.githubusercontent.com:sub") != expected_subject: raise SystemExit("PUBLISHER_TRUST_SUBJECT_MISMATCH")
allowed_repo_actions = {"ecr:BatchCheckLayerAvailability","ecr:GetDownloadUrlForLayer","ecr:BatchGetImage","ecr:InitiateLayerUpload","ecr:UploadLayerPart","ecr:CompleteLayerUpload","ecr:PutImage","ecr:DescribeImages"}
statements = policy.get("Statement", [])
if isinstance(statements, dict): statements = [statements]
seen_auth = seen_repo = False
for stmt in statements:
    actions = stmt.get("Action", [])
    if isinstance(actions, str): actions = [actions]
    actions = set(actions)
    resource = stmt.get("Resource")
    if actions == {"ecr:GetAuthorizationToken"} and resource == "*": seen_auth = True
    elif actions == allowed_repo_actions and resource == repo_arn: seen_repo = True
    else: raise SystemExit("PUBLISHER_POLICY_UNEXPECTED_STATEMENT")
if not seen_auth: raise SystemExit("PUBLISHER_POLICY_AUTH_STATEMENT_MISSING")
if not seen_repo: raise SystemExit("PUBLISHER_POLICY_REPOSITORY_SCOPE_MISSING")
PY

if aws ecr describe-images --region "$AWS_REGION" --repository-name "$REPOSITORY_NAME" --image-ids imageTag="git-${EXPECTED_HEAD}" >/dev/null 2>&1; then
  fail "IMMUTABLE_IMAGE_TAG_ALREADY_EXISTS"
fi

if [[ "$EXECUTE_PUBLISH" == false ]]; then
  printf '%s\n' \
    "BackendImagePublisherPreparation=passed" \
    "RepositoryHead=${ACTUAL_HEAD:0:12}" \
    "RuntimeApplyHead=${RUNTIME_APPLY_HEAD:0:12}" \
    "RuntimeApplyVerified=true" \
    "PublisherRoleOutputValid=true" \
    "PublisherRoleTrustVerified=true" \
    "PublisherPolicyVerified=true" \
    "PublisherRepositoryScopeVerified=true" \
    "EnvironmentName=${ENVIRONMENT}" \
    "EnvironmentVariablesRequired=3" \
    "ImmutableImageTag=git-${EXPECTED_HEAD}" \
    "Workflow=${WORKFLOW}" \
    "WorkflowRef=${SOURCE_BRANCH}" \
    "GitHubMutation=none" \
    "AwsMutation=none" \
    "DockerBuildExecuted=false" \
    "KubernetesMutation=false"
  exit 0
fi

for command_name in gh; do
  command -v "$command_name" >/dev/null 2>&1 || fail "REQUIRED_COMMAND_NOT_FOUND: $command_name"
done

gh auth status --hostname github.com >/dev/null 2>&1 || fail "GITHUB_AUTH_UNAVAILABLE"
gh api --method PUT -H "Accept: application/vnd.github+json" "repos/${REPO}/environments/${ENVIRONMENT}" >/dev/null
printf '%s' "$ROLE_ARN" | gh variable set AWS_ROLE_TO_ASSUME --env "$ENVIRONMENT" --repo "$REPO" >/dev/null
printf '%s' "$AWS_REGION" | gh variable set AWS_REGION --env "$ENVIRONMENT" --repo "$REPO" >/dev/null
printf '%s' "$EXPECTED_ACCOUNT_ID" | gh variable set EXPECTED_AWS_ACCOUNT_ID --env "$ENVIRONMENT" --repo "$REPO" >/dev/null

gh workflow run "$WORKFLOW" --repo "$REPO" --ref "$SOURCE_BRANCH" -f "image_uri=${IMAGE_URI}" -f "push_image=true"
sleep 5
RUN_JSON="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --branch "$SOURCE_BRANCH" --limit 1 --json databaseId,url,headSha)"
RUN_ID="$(${PYTHON_CMD[@]} -c 'import json,sys; print(json.loads(sys.argv[1])[0]["databaseId"])' "$RUN_JSON")"
RUN_URL="$(${PYTHON_CMD[@]} -c 'import json,sys; print(json.loads(sys.argv[1])[0]["url"])' "$RUN_JSON")"
RUN_HEAD="$(${PYTHON_CMD[@]} -c 'import json,sys; print(json.loads(sys.argv[1])[0]["headSha"])' "$RUN_JSON")"
[[ "$RUN_HEAD" == "$EXPECTED_HEAD" ]] || fail "WORKFLOW_RUN_HEAD_MISMATCH"
printf '%s\n' \
  "BackendImagePublishDispatch=success" \
  "EnvironmentVariablesConfigured=true" \
  "Workflow=${WORKFLOW}" \
  "PushImage=true" \
  "RunId=${RUN_ID}" \
  "RunUrl=${RUN_URL}" \
  "TerraformApplyExecuted=false" \
  "TerraformDestroyExecuted=false" \
  "KubernetesMutation=false" \
  "GitHubMutation=publisher-environment-vars-and-dispatch" \
  "AwsMutation=deferred-to-workflow-image-push"
