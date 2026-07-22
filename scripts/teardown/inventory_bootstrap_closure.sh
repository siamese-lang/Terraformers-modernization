#!/usr/bin/env bash
# Read-only bootstrap-closure inventory for AWS CloudShell or an independent
# administrator Linux shell. This script is not supported on Windows Git Bash.

set -u -o pipefail

EXPECTED_ACCOUNT_ID="${EXPECTED_ACCOUNT_ID:-024863981627}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
STATE_BUCKET="${STATE_BUCKET:-terraformers-modernization-024863981627-apne2-state}"
# Use the existing GitHub Environment/workflow value; do not invent a prefix.
STATE_PREFIX="${STATE_PREFIX:?STATE_PREFIX must equal AWS_TERRAFORM_STATE_PREFIX from the GitHub Environment}"

readonly RUNTIME_STATES=(frontend-delivery rag-runtime eks-runtime stateful-dependencies runtime-dependencies network)
readonly REQUIRED_ROLES=(terraformers-live-terraform-plan terraformers-live-terraform-apply terraformers-live-teardown)
readonly BOOTSTRAP_ADDRESSES=(
  aws_iam_policy.terraform_apply_operations_visibility_create
  aws_iam_role.terraform_apply aws_iam_role.terraform_plan
  aws_iam_role_policy.terraform_apply_iam_mutation aws_iam_role_policy.terraform_apply_rag_runtime_create
  aws_iam_role_policy.terraform_apply_state_access aws_iam_role_policy.terraform_state_access
  aws_iam_role_policy_attachment.terraform_apply_operations_visibility_create
  aws_iam_role_policy_attachment.terraform_apply_read_only aws_iam_role_policy_attachment.terraform_plan_read_only
  aws_s3_bucket.terraform_state aws_s3_bucket_ownership_controls.terraform_state aws_s3_bucket_policy.terraform_state
  aws_s3_bucket_public_access_block.terraform_state aws_s3_bucket_server_side_encryption_configuration.terraform_state
  aws_s3_bucket_versioning.terraform_state
)
readonly OIDC_PROVIDER_ARN="arn:aws:iam::${EXPECTED_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
readonly SECRET_NAME="terraformers/dev/backend/runtime"
readonly OUTPUT_DIR="artifacts/bootstrap-closure-inventory"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
mkdir -p "${OUTPUT_DIR}"
API_ERRORS=()
AWS_JSON='{}'

record_error() { API_ERRORS+=("$1"); }
aws_json() {
  local label="$1"; shift
  if ! AWS_JSON="$(aws "$@" --output json 2>"${WORK_DIR}/aws-error")"; then
    record_error "${label}"
    AWS_JSON='{}'
    return 1
  fi
  jq -e . >/dev/null 2>&1 <<<"${AWS_JSON}" || { record_error "${label}"; AWS_JSON='{}'; return 1; }
}
bool() { if "$@"; then printf 'true'; else printf 'false'; fi; }

# Identity is deliberately captured before all other calls and only its account and ARN are retained.
identity_ok=false
caller_arn=''
if aws_json identity sts get-caller-identity; then
  actual_account="$(jq -r '.Account // empty' <<<"${AWS_JSON}")"
  caller_arn="$(jq -r '.Arn // empty' <<<"${AWS_JSON}")"
  [ "${actual_account}" = "${EXPECTED_ACCOUNT_ID}" ] && identity_ok=true
fi
independent_identity=true
for role in "${REQUIRED_ROLES[@]}"; do
  [[ "${caller_arn}" == *":role/${role}" || "${caller_arn}" == *":assumed-role/${role}/"* ]] && independent_identity=false
done

runtime_counts='{}'
runtime_states_zero=true
for component in "${RUNTIME_STATES[@]}"; do
  state_file="${WORK_DIR}/${component}.tfstate"
  if aws s3api get-object --bucket "${STATE_BUCKET}" --key "${STATE_PREFIX%/}/${component}/terraform.tfstate" "${state_file}" >/dev/null 2>"${WORK_DIR}/aws-error"; then
    count="$(jq '[.resources[]? | select((.mode // "managed") == "managed") | (.instances | length)] | add // 0' "${state_file}" 2>/dev/null)" || { record_error "runtime-state-${component}"; count=0; runtime_states_zero=false; }
    runtime_counts="$(jq --arg component "${component}" --argjson count "${count}" '. + {($component): $count}' <<<"${runtime_counts}")"
    [ "${count}" -eq 0 ] || runtime_states_zero=false
  else
    record_error "runtime-state-${component}"
    runtime_counts="$(jq --arg component "${component}" '. + {($component): null}' <<<"${runtime_counts}")"
    runtime_states_zero=false
  fi
done

bootstrap_readable=false; bootstrap_managed_count=null; bootstrap_data_count=null; bootstrap_addresses='[]'; bootstrap_address_difference='[]'
bootstrap_file="${WORK_DIR}/bootstrap.tfstate"
if aws s3api get-object --bucket "${STATE_BUCKET}" --key "${STATE_PREFIX%/}/bootstrap/terraform.tfstate" "${bootstrap_file}" >/dev/null 2>"${WORK_DIR}/aws-error"; then
  bootstrap_readable=true
  bootstrap_managed_count="$(jq '[.resources[]? | select((.mode // "managed") == "managed") | (.instances | length)] | add // 0' "${bootstrap_file}")"
  bootstrap_data_count="$(jq '[.resources[]? | select(.mode == "data") | (.instances | length)] | add // 0' "${bootstrap_file}")"
  if ! bootstrap_addresses="$(jq -c '
    [
      .resources[]?
      | select((.mode // "managed") == "managed")
      | if (
          (.type | type) == "string" and .type != "" and
          (.name | type) == "string" and .name != "" and
          ((.module // "") | type) == "string"
        )
        then
          if (.module // "") == ""
          then "\(.type).\(.name)"
          else "\(.module).\(.type).\(.name)"
          end
        else null
        end
    ] | sort
  ' "${bootstrap_file}")"; then
    record_error bootstrap-state-parsing
    bootstrap_addresses='[]'
  fi
  if ! jq -e 'all(.[]; type == "string" and length > 0) and (length == (unique | length))' >/dev/null <<<"${bootstrap_addresses}"; then
    record_error bootstrap-state-addresses
  fi
  expected_addresses="$(printf '%s\n' "${BOOTSTRAP_ADDRESSES[@]}" | jq -R . | jq -s 'sort')"
  bootstrap_address_difference="$(jq -cn --argjson expected "${expected_addresses}" --argjson live "${bootstrap_addresses}" '{missing_from_live: ($expected - $live), unexpected_live: ($live - $expected)}')"
else record_error bootstrap-state; fi

bucket_present=false; bucket_versioning='unknown'; object_version_count=null; delete_marker_count=null; current_object_count=null; multipart_upload_count=null; terraform_lock_version_count=null
if aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>"${WORK_DIR}/aws-error"; then
  bucket_present=true
  if aws_json bucket-versioning s3api get-bucket-versioning --bucket "${STATE_BUCKET}"; then bucket_versioning="$(jq -r '.Status // "Disabled"' <<<"${AWS_JSON}")"; fi
  if aws_json bucket-versions s3api list-object-versions --bucket "${STATE_BUCKET}"; then
    object_version_count="$(jq '[.Versions[]?] | length' <<<"${AWS_JSON}")"; delete_marker_count="$(jq '[.DeleteMarkers[]?] | length' <<<"${AWS_JSON}")"
    terraform_lock_version_count="$(jq '[.Versions[]?, .DeleteMarkers[]? | select(.Key | endswith(".tflock"))] | length' <<<"${AWS_JSON}")"
  fi
  if aws_json bucket-current-objects s3api list-objects-v2 --bucket "${STATE_BUCKET}"; then current_object_count="$(jq '[.Contents[]?] | length' <<<"${AWS_JSON}")"; fi
  if aws_json bucket-multipart-uploads s3api list-multipart-uploads --bucket "${STATE_BUCKET}"; then multipart_upload_count="$(jq '[.Uploads[]?] | length' <<<"${AWS_JSON}")"; fi
else record_error state-bucket; fi

roles_json='[]'; required_roles_present=true
for role in "${REQUIRED_ROLES[@]}"; do
  exists=false; attached='[]'; inline='[]'; profiles=0; boundary=false; trusts_oidc=false
  if aws_json "role-${role}" iam get-role --role-name "${role}"; then
    exists=true
    trusts_oidc="$(jq --arg arn "${OIDC_PROVIDER_ARN}" '[.Role.AssumeRolePolicyDocument.Statement[]?.Principal.Federated? | if type == "array" then .[] else . end | select(. == $arn)] | length > 0' <<<"${AWS_JSON}")"
    boundary="$(jq '.Role.PermissionsBoundary != null' <<<"${AWS_JSON}")"
    if aws_json "role-attached-${role}" iam list-attached-role-policies --role-name "${role}"; then attached="$(jq -c '[.AttachedPolicies[]? | {name: .PolicyName, arn: .PolicyArn}]' <<<"${AWS_JSON}")"; fi
    if aws_json "role-inline-${role}" iam list-role-policies --role-name "${role}"; then inline="$(jq -c '[.PolicyNames[]?]' <<<"${AWS_JSON}")"; fi
    if aws_json "role-profiles-${role}" iam list-instance-profiles-for-role --role-name "${role}"; then profiles="$(jq '[.InstanceProfiles[]?] | length' <<<"${AWS_JSON}")"; fi
  else required_roles_present=false; fi
  roles_json="$(jq -c --arg name "${role}" --argjson exists "${exists}" --argjson attached "${attached}" --argjson inline "${inline}" --argjson profiles "${profiles}" --argjson boundary "${boundary}" --argjson trust "${trusts_oidc}" '. + [{name: $name, exists: $exists, attached_managed_policies: $attached, inline_policy_names: $inline, instance_profile_count: $profiles, permissions_boundary_present: $boundary, trusts_github_oidc: $trust}]' <<<"${roles_json}")"
done

customer_policies='[]'
if aws_json terraformers-customer-policies iam list-policies --scope Local; then customer_policies="$(jq -c '[.Policies[]? | select((.PolicyName | startswith("terraformers-"))) | {name: .PolicyName, arn: .Arn}]' <<<"${AWS_JSON}")"; fi

oidc_present=false; oidc_client_ids='[]'; oidc_thumbprint_count=null; oidc_roles='[]'; oidc_contract='blocked_by_inventory_error'
if aws_json oidc-provider iam get-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_PROVIDER_ARN}"; then
  oidc_present=true; oidc_client_ids="$(jq -c '.ClientIDList // []' <<<"${AWS_JSON}")"; oidc_thumbprint_count="$(jq '[.ThumbprintList[]?] | length' <<<"${AWS_JSON}")"
  if aws_json all-role-names iam list-roles; then
    oidc_scan_ok=true
    while IFS= read -r role; do
      [ -n "${role}" ] || continue
      if aws_json "oidc-trust-${role}" iam get-role --role-name "${role}"; then
        if jq -e --arg arn "${OIDC_PROVIDER_ARN}" '[.Role.AssumeRolePolicyDocument.Statement[]?.Principal.Federated? | if type == "array" then .[] else . end | select(. == $arn)] | length > 0' >/dev/null <<<"${AWS_JSON}"; then oidc_roles="$(jq -c --arg role "${role}" '. + [$role]' <<<"${oidc_roles}")"; fi
      else oidc_scan_ok=false; fi
    done < <(jq -r '.Roles[]?.RoleName' <<<"${AWS_JSON}")
    if [ "${oidc_scan_ok}" = true ]; then
      if jq -e 'all(.[]; startswith("terraformers-"))' >/dev/null <<<"${oidc_roles}"; then oidc_contract=terraformers_only; else oidc_contract=blocked_by_non_terraformers_role; fi
    fi
  fi
fi

active_secret_count=null; pending_secret_count=null; secret_absent=false; secret_deleted_date_present=false
if aws_json runtime-secret secretsmanager list-secrets --region "${AWS_REGION}" --include-planned-deletion; then
  matching="$(jq -c --arg name "${SECRET_NAME}" '[.SecretList[]? | select(.Name == $name)]' <<<"${AWS_JSON}")"
  active_secret_count="$(jq '[.[] | select(.DeletedDate == null)] | length' <<<"${matching}")"; pending_secret_count="$(jq '[.[] | select(.DeletedDate != null)] | length' <<<"${matching}")"
  [ "$(jq 'length' <<<"${matching}")" -eq 0 ] && secret_absent=true
  [ "${pending_secret_count}" -gt 0 ] && secret_deleted_date_present=true
fi

if [ "${runtime_states_zero}" = true ] && [ "${bootstrap_readable}" = true ] && [ "${bucket_present}" = true ] && [ "${required_roles_present}" = true ] && [ "${oidc_present}" = true ] && [ "${oidc_contract}" = terraformers_only ] && [ "${independent_identity}" = true ] && [ "${identity_ok}" = true ] && [ "${#API_ERRORS[@]}" -eq 0 ]; then contract=ready_for_deletion_command_review
elif [ "${#API_ERRORS[@]}" -gt 0 ] || [ "${identity_ok}" != true ]; then contract=blocked_by_inventory_error
elif [ "${runtime_states_zero}" != true ]; then contract=blocked_by_runtime_state
elif [ "${oidc_contract}" = blocked_by_non_terraformers_role ]; then contract=blocked_by_oidc_shared_ownership
else contract=blocked_by_inventory_error; fi

if [ "${#API_ERRORS[@]}" -eq 0 ]; then
  api_errors_json='[]'
else
  api_errors_json="$(
    printf '%s\n' "${API_ERRORS[@]}" |
    jq -R . |
    jq -s '.'
  )"
fi

jq -n --arg account "${EXPECTED_ACCOUNT_ID}" --arg region "${AWS_REGION}" --arg bucket "${STATE_BUCKET}" --arg prefix "${STATE_PREFIX%/}" --arg caller "${caller_arn}" --arg bucketVersioning "${bucket_versioning}" --arg oidcArn "${OIDC_PROVIDER_ARN}" --arg secret "${SECRET_NAME}" --arg contract "${contract}" --arg oidcContract "${oidc_contract}" --argjson runtime "${runtime_counts}" --argjson managed "${bootstrap_managed_count}" --argjson data "${bootstrap_data_count}" --argjson addresses "${bootstrap_addresses}" --argjson differences "${bootstrap_address_difference}" --argjson versions "${object_version_count}" --argjson markers "${delete_marker_count}" --argjson objects "${current_object_count}" --argjson uploads "${multipart_upload_count}" --argjson locks "${terraform_lock_version_count}" --argjson roles "${roles_json}" --argjson policies "${customer_policies}" --argjson clientIds "${oidc_client_ids}" --argjson thumbs "${oidc_thumbprint_count}" --argjson oidcRoles "${oidc_roles}" --argjson active "${active_secret_count}" --argjson pending "${pending_secret_count}" --argjson errors "${api_errors_json}" --argjson independent "${independent_identity}" --argjson runtimeZero "${runtime_states_zero}" --argjson bootstrapReadable "${bootstrap_readable}" --argjson bucketPresent "${bucket_present}" --argjson oidcPresent "${oidc_present}" --argjson requiredRoles "${required_roles_present}" --argjson absent "${secret_absent}" --argjson deletedDate "${secret_deleted_date_present}" --argjson boundaryMatch "$( [ "${bootstrap_managed_count}" = 16 ] && printf true || printf false )" '{expected_account_id:$account, aws_region:$region, state_bucket:$bucket, state_prefix:$prefix, caller_arn:$caller, independent_identity_confirmed:$independent, runtime_states:$runtime, runtime_states_zero:$runtimeZero, bootstrap_state_readable:$bootstrapReadable, bootstrap_managed_count:$managed, bootstrap_data_source_count:$data, bootstrap_managed_addresses:$addresses, bootstrap_expected_managed_count:16, bootstrap_managed_count_matches_expected:$boundaryMatch, bootstrap_address_difference:$differences, state_bucket_present:$bucketPresent, state_bucket_versioning:$bucketVersioning, state_bucket_object_version_count:$versions, state_bucket_delete_marker_count:$markers, state_bucket_current_object_count:$objects, state_bucket_multipart_upload_count:$uploads, terraform_lock_object_version_count:$locks, required_roles:$roles, required_roles_present:$requiredRoles, terraformers_customer_managed_policies:$policies, github_oidc_provider_arn:$oidcArn, github_oidc_present:$oidcPresent, github_oidc_client_ids:$clientIds, github_oidc_thumbprint_count:$thumbs, github_oidc_trusting_roles:$oidcRoles, oidc_ownership_contract:$oidcContract, terraformers_oidc_trust_only:($oidcContract == "terraformers_only"), runtime_secret_name:$secret, active_runtime_secret_count:$active, pending_runtime_secret_deletion_count:$pending, runtime_secret_absent:$absent, runtime_secret_deleted_date_present:$deletedDate, inventory_api_error_labels:$errors, inventory_contract:$contract}' > "${OUTPUT_DIR}/bootstrap-closure-inventory.json"

{
  echo "inventory_mode=read-only"; echo "cloudshell_or_independent_linux_only=true"; echo "runtime_states_zero=${runtime_states_zero}"; echo "bootstrap_state_readable=${bootstrap_readable}"; echo "bootstrap_managed_count=${bootstrap_managed_count}"; echo "state_bucket_present=${bucket_present}"; echo "github_oidc_present=${oidc_present}"; echo "terraformers_oidc_trust_only=$( [ "${oidc_contract}" = terraformers_only ] && echo true || echo false )"; echo "required_roles_present=${required_roles_present}"; echo "active_runtime_secret_count=${active_secret_count}"; echo "pending_runtime_secret_deletion_count=${pending_secret_count}"; echo "independent_identity_confirmed=${independent_identity}"; echo "inventory_contract=${contract}"
} > "${OUTPUT_DIR}/execution-summary.txt"

echo "Sanitized inventory written to ${OUTPUT_DIR}. No deletion command was executed."
