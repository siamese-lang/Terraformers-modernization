#!/usr/bin/env bash
set -euo pipefail

STATE_JSON="${1:?state json required}"
EVIDENCE_DIR="${2:?evidence directory required}"
REGION="${AWS_REGION:-ap-northeast-2}"
OUT="${EVIDENCE_DIR}/network-vpc-residual-cleanup.json"
mkdir -p "${EVIDENCE_DIR}"

[[ "${GITHUB_ACTIONS:-}" == true ]]
[[ "${GITHUB_WORKFLOW:-}" == "AWS Runtime Teardown" ]]
[[ "${GITHUB_EVENT_NAME:-}" == workflow_dispatch ]]

vpc_id="$(jq -r '
  .resources[]?
  | select(.mode == "managed" and .type == "aws_vpc" and .name == "runtime")
  | .instances[]?.attributes.id // empty
' "${STATE_JSON}" | head -n1)"
[[ "${vpc_id}" == vpc-* ]]

vpc_json="$(aws ec2 describe-vpcs --region "${REGION}" --vpc-ids "${vpc_id}" --output json 2>/dev/null || true)"
if [[ -z "${vpc_json}" ]]; then
  jq -n '{stage:"network",already_absent:true,vpc_deleted:true,contract:"passed"}' > "${OUT}"
  exit 0
fi

approved="$(jq -r '
  [.Vpcs[0].Tags[]? | select(
    (.Key == "Project" and ((.Value | ascii_downcase) == "terraformers" or (.Value | ascii_downcase) == "terraformers-modernization"))
    or (.Key == "Name" and ((.Value | ascii_downcase) | contains("terraformers")))
  )] | length
' <<<"${vpc_json}")"
[[ "${approved}" -gt 0 ]]

inventory() {
  local phase="$1"
  local eni_json sg_json subnet_json endpoint_json nat_json rtb_json acl_json igw_json
  eni_json="$(aws ec2 describe-network-interfaces --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --output json)"
  sg_json="$(aws ec2 describe-security-groups --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --output json)"
  subnet_json="$(aws ec2 describe-subnets --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --output json)"
  endpoint_json="$(aws ec2 describe-vpc-endpoints --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --output json)"
  nat_json="$(aws ec2 describe-nat-gateways --region "${REGION}" --filter "Name=vpc-id,Values=${vpc_id}" --output json)"
  rtb_json="$(aws ec2 describe-route-tables --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --output json)"
  acl_json="$(aws ec2 describe-network-acls --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --output json)"
  igw_json="$(aws ec2 describe-internet-gateways --region "${REGION}" --filters "Name=attachment.vpc-id,Values=${vpc_id}" --output json)"
  jq -n \
    --arg phase "${phase}" \
    --argjson eni "${eni_json}" \
    --argjson sg "${sg_json}" \
    --argjson subnet "${subnet_json}" \
    --argjson endpoint "${endpoint_json}" \
    --argjson nat "${nat_json}" \
    --argjson rtb "${rtb_json}" \
    --argjson acl "${acl_json}" \
    --argjson igw "${igw_json}" \
    '{
      phase:$phase,
      network_interface_count:($eni.NetworkInterfaces | length),
      network_interface_groups:($eni.NetworkInterfaces | group_by([.InterfaceType, .RequesterManaged, .Status]) | map({key:(.[0].InterfaceType + "|requester=" + (.[0].RequesterManaged|tostring) + "|status=" + .[0].Status), value:length}) | from_entries),
      nondefault_security_group_count:([$sg.SecurityGroups[] | select(.GroupName != "default")] | length),
      subnet_count:($subnet.Subnets | length),
      vpc_endpoint_count:($endpoint.VpcEndpoints | length),
      active_nat_gateway_count:([$nat.NatGateways[] | select(.State != "deleted" and .State != "failed")] | length),
      nonmain_route_table_count:([$rtb.RouteTables[] | select([.Associations[]? | .Main == true] | any | not)] | length),
      nondefault_network_acl_count:([$acl.NetworkAcls[] | select(.IsDefault != true)] | length),
      internet_gateway_count:($igw.InternetGateways | length)
    }'
}

initial="$(inventory initial)"

aws elbv2 describe-load-balancers --region "${REGION}" --output json |
  jq -r --arg vpc "${vpc_id}" '.LoadBalancers[]? | select(.VpcId == $vpc) | .LoadBalancerArn' |
  while IFS= read -r arn; do [[ -z "${arn}" ]] || aws elbv2 delete-load-balancer --region "${REGION}" --load-balancer-arn "${arn}"; done

aws elb describe-load-balancers --region "${REGION}" --output json |
  jq -r --arg vpc "${vpc_id}" '.LoadBalancerDescriptions[]? | select(.VPCId == $vpc) | .LoadBalancerName' |
  while IFS= read -r name; do [[ -z "${name}" ]] || aws elb delete-load-balancer --region "${REGION}" --load-balancer-name "${name}"; done

mapfile -t endpoint_ids < <(aws ec2 describe-vpc-endpoints --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --query 'VpcEndpoints[].VpcEndpointId' --output text | tr '\t' '\n' | sed '/^$/d')
if (( ${#endpoint_ids[@]} > 0 )); then aws ec2 delete-vpc-endpoints --region "${REGION}" --vpc-endpoint-ids "${endpoint_ids[@]}" >/dev/null; fi

mapfile -t nat_ids < <(aws ec2 describe-nat-gateways --region "${REGION}" --filter "Name=vpc-id,Values=${vpc_id}" --output json | jq -r '.NatGateways[]? | select(.State != "deleted" and .State != "failed") | .NatGatewayId')
for id in "${nat_ids[@]}"; do aws ec2 delete-nat-gateway --region "${REGION}" --nat-gateway-id "${id}" >/dev/null || true; done
for _ in $(seq 1 18); do
  active_nat="$(aws ec2 describe-nat-gateways --region "${REGION}" --filter "Name=vpc-id,Values=${vpc_id}" --output json | jq '[.NatGateways[]? | select(.State != "deleted" and .State != "failed")] | length')"
  [[ "${active_nat}" -eq 0 ]] && break
  sleep 10
done

for _ in $(seq 1 6); do
  eni_json="$(aws ec2 describe-network-interfaces --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --output json)"
  jq -r '.NetworkInterfaces[]? | select(.RequesterManaged != true and .Attachment.AttachmentId != null) | .Attachment.AttachmentId' <<<"${eni_json}" |
    while IFS= read -r attachment; do [[ -z "${attachment}" ]] || aws ec2 detach-network-interface --region "${REGION}" --attachment-id "${attachment}" --force >/dev/null 2>&1 || true; done
  jq -r '.NetworkInterfaces[]? | select(.RequesterManaged != true and .Attachment.AttachmentId == null) | .NetworkInterfaceId' <<<"${eni_json}" |
    while IFS= read -r eni; do [[ -z "${eni}" ]] || aws ec2 delete-network-interface --region "${REGION}" --network-interface-id "${eni}" >/dev/null 2>&1 || true; done
  sleep 5
done

sg_json="$(aws ec2 describe-security-groups --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --output json)"
jq -r '.SecurityGroups[]? | select(.GroupName != "default") | .GroupId' <<<"${sg_json}" |
  while IFS= read -r sg; do
    [[ -z "${sg}" ]] && continue
    ingress="$(jq -c --arg sg "${sg}" '.SecurityGroups[] | select(.GroupId == $sg) | .IpPermissions' <<<"${sg_json}")"
    egress="$(jq -c --arg sg "${sg}" '.SecurityGroups[] | select(.GroupId == $sg) | .IpPermissionsEgress' <<<"${sg_json}")"
    [[ "${ingress}" == "[]" ]] || aws ec2 revoke-security-group-ingress --region "${REGION}" --group-id "${sg}" --ip-permissions "${ingress}" >/dev/null 2>&1 || true
    [[ "${egress}" == "[]" ]] || aws ec2 revoke-security-group-egress --region "${REGION}" --group-id "${sg}" --ip-permissions "${egress}" >/dev/null 2>&1 || true
  done
for _ in $(seq 1 6); do
  aws ec2 describe-security-groups --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --output json |
    jq -r '.SecurityGroups[]? | select(.GroupName != "default") | .GroupId' |
    while IFS= read -r sg; do [[ -z "${sg}" ]] || aws ec2 delete-security-group --region "${REGION}" --group-id "${sg}" >/dev/null 2>&1 || true; done
  sleep 5
done

aws ec2 describe-subnets --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --query 'Subnets[].SubnetId' --output text |
  tr '\t' '\n' | while IFS= read -r subnet; do [[ -z "${subnet}" ]] || aws ec2 delete-subnet --region "${REGION}" --subnet-id "${subnet}" >/dev/null 2>&1 || true; done

rt_json="$(aws ec2 describe-route-tables --region "${REGION}" --filters "Name=vpc-id,Values=${vpc_id}" --output json)"
jq -r '.RouteTables[]? | select([.Associations[]? | .Main == true] | any | not) | .Associations[]?.RouteTableAssociationId' <<<"${rt_json}" |
  while IFS= read -r association; do [[ -z "${association}" ]] || aws ec2 disassociate-route-table --region "${REGION}" --association-id "${association}" >/dev/null 2>&1 || true; done
jq -r '.RouteTables[]? | select([.Associations[]? | .Main == true] | any | not) | .RouteTableId' <<<"${rt_json}" |
  while IFS= read -r table; do [[ -z "${table}" ]] || aws ec2 delete-route-table --region "${REGION}" --route-table-id "${table}" >/dev/null 2>&1 || true; done

aws ec2 describe-internet-gateways --region "${REGION}" --filters "Name=attachment.vpc-id,Values=${vpc_id}" --query 'InternetGateways[].InternetGatewayId' --output text |
  tr '\t' '\n' | while IFS= read -r igw; do
    [[ -z "${igw}" ]] && continue
    aws ec2 detach-internet-gateway --region "${REGION}" --internet-gateway-id "${igw}" --vpc-id "${vpc_id}" >/dev/null 2>&1 || true
    aws ec2 delete-internet-gateway --region "${REGION}" --internet-gateway-id "${igw}" >/dev/null 2>&1 || true
  done

last_error=""
for attempt in $(seq 1 6); do
  if aws ec2 delete-vpc --region "${REGION}" --vpc-id "${vpc_id}" 2>"${RUNNER_TEMP}/delete-vpc.err"; then
    last_error=""
    break
  fi
  last_error="$(tr '\n' ' ' < "${RUNNER_TEMP}/delete-vpc.err" | sed -E 's/(vpc|eni|sg|subnet|rtb|acl|igw|vpce|nat)-[0-9a-f]+/<resource-id>/g' | cut -c1-500)"
  sleep 10
done

if aws ec2 describe-vpcs --region "${REGION}" --vpc-ids "${vpc_id}" >/dev/null 2>&1; then
  final="$(inventory final)"
  jq -n --argjson initial "${initial}" --argjson final "${final}" --arg error "${last_error}" \
    '{stage:"network",approved_vpc_tag_verified:true,initial:$initial,final:$final,vpc_deleted:false,delete_vpc_error:$error,contract:"failed"}' > "${OUT}"
  echo "network_vpc_recovery_failed=${last_error}" >&2
  exit 1
fi

jq -n --argjson initial "${initial}" \
  '{stage:"network",approved_vpc_tag_verified:true,initial:$initial,vpc_deleted:true,contract:"passed"}' > "${OUT}"
