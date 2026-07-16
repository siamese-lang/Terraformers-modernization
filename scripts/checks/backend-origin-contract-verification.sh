#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NETWORK_MAIN="${REPO_ROOT}/infra/terraform/envs/aws-runtime-network/main.tf"
EKS_DIR="${REPO_ROOT}/infra/terraform/envs/eks-runtime"
FRONTEND_DIR="${REPO_ROOT}/infra/terraform/envs/frontend-delivery"
TEMPLATE_DIR="${REPO_ROOT}/infra/kubernetes/aws-runtime-origin"
POLICY_FILE="${EKS_DIR}/policies/aws-load-balancer-controller-v3.4.2.json"
EVIDENCE_DIR="${REPO_ROOT}/artifacts/backend-origin-contract"
FIXTURE_DIR="${EVIDENCE_DIR}/fixtures"
PACKAGE_DIR="${EVIDENCE_DIR}/package"
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

rm -rf "${EVIDENCE_DIR}"
mkdir -p "${FIXTURE_DIR}"

for required_file in \
  "${NETWORK_MAIN}" \
  "${EKS_DIR}/load_balancer_controller.tf" \
  "${EKS_DIR}/outputs.tf" \
  "${EKS_DIR}/variables.tf" \
  "${POLICY_FILE}" \
  "${TEMPLATE_DIR}/aws-load-balancer-controller-serviceaccount.yaml" \
  "${TEMPLATE_DIR}/aws-load-balancer-controller-values.yaml" \
  "${TEMPLATE_DIR}/backend-origin-ingress.yaml" \
  "${FRONTEND_DIR}/main.tf" \
  "${FRONTEND_DIR}/variables.tf" \
  "${FRONTEND_DIR}/versions.tf"; do
  test -s "${required_file}" || {
    echo "Expected non-empty file: ${required_file}" >&2
    exit 1
  }
done

# Network prerequisites for CloudFront VPC origins and an internal ALB.
assert_contains 'resource "aws_internet_gateway" "runtime"' "${NETWORK_MAIN}" "Runtime VPC must retain an Internet Gateway for CloudFront VPC origin eligibility."
assert_contains '"kubernetes.io/role/internal-elb"[[:space:]]*=[[:space:]]*"1"' "${NETWORK_MAIN}" "Private subnets must be tagged for internal load balancers."
assert_contains 'resource "aws_subnet" "private"' "${NETWORK_MAIN}" "Private subnets are required for the backend origin."

# Dedicated controller identity and CloudFront-only frontend security group.
assert_contains 'system:serviceaccount:\$\{var.load_balancer_controller_namespace\}:\$\{var.load_balancer_controller_service_account_name\}' "${EKS_DIR}/load_balancer_controller.tf" "Controller IRSA trust subject is missing."
assert_contains 'com.amazonaws.global.cloudfront.origin-facing' "${EKS_DIR}/load_balancer_controller.tf" "CloudFront origin-facing managed prefix list is required."
assert_contains 'prefix_list_ids[[:space:]]*=[[:space:]]*\[data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id\]' "${EKS_DIR}/load_balancer_controller.tf" "Private ALB ingress must be limited to the CloudFront managed prefix list."
assert_contains 'from_port[[:space:]]*=[[:space:]]*8080' "${EKS_DIR}/load_balancer_controller.tf" "Private ALB egress must target the backend application port."
assert_contains 'cidr_blocks[[:space:]]*=[[:space:]]*\[var.vpc_cidr_block\]' "${EKS_DIR}/load_balancer_controller.tf" "Private ALB egress must remain inside the runtime VPC."
assert_not_contains '0\.0\.0\.0/0' "${EKS_DIR}/load_balancer_controller.tf" "Backend origin security group must not expose public CIDR ingress or egress."

python3 -m json.tool "${POLICY_FILE}" >"${EVIDENCE_DIR}/aws-load-balancer-controller-policy.normalized.json"
sha256sum "${POLICY_FILE}" >"${EVIDENCE_DIR}/aws-load-balancer-controller-policy.sha256"
assert_contains 'elasticloadbalancing:CreateLoadBalancer' "${POLICY_FILE}" "Pinned controller policy must include load balancer creation permission."
assert_contains 'elasticloadbalancing:RegisterTargets' "${POLICY_FILE}" "Pinned controller policy must include target registration permission."

# Controller and Ingress templates must stay private and use Pod IP targets.
INGRESS_TEMPLATE="${TEMPLATE_DIR}/backend-origin-ingress.yaml"
assert_contains 'alb.ingress.kubernetes.io/scheme:[[:space:]]*internal' "${INGRESS_TEMPLATE}" "Backend origin ALB must be internal."
assert_contains 'alb.ingress.kubernetes.io/target-type:[[:space:]]*ip' "${INGRESS_TEMPLATE}" "Backend origin ALB must register Pod IP targets."
assert_contains 'alb.ingress.kubernetes.io/manage-backend-security-group-rules:[[:space:]]*"true"' "${INGRESS_TEMPLATE}" "Controller must reconcile backend security-group rules."
assert_contains 'alb.ingress.kubernetes.io/healthcheck-path:[[:space:]]*/actuator/health' "${INGRESS_TEMPLATE}" "Target health must use the backend health endpoint."
assert_contains 'path:[[:space:]]*/api' "${INGRESS_TEMPLATE}" "Ingress must expose only the application API prefix."
assert_not_contains 'scheme:[[:space:]]*internet-facing' "${INGRESS_TEMPLATE}" "Internet-facing ALB is forbidden in this contract."
assert_not_contains 'path:[[:space:]]*/actuator' "${INGRESS_TEMPLATE}" "Actuator must not be a listener route."

# CloudFront must use the private ALB through a VPC origin, not a public custom origin.
assert_contains 'resource "aws_cloudfront_vpc_origin" "backend"' "${FRONTEND_DIR}/main.tf" "CloudFront VPC origin resource is missing."
assert_contains 'data "aws_lb" "backend_origin"' "${FRONTEND_DIR}/main.tf" "Frontend delivery must resolve the approved ALB by ARN."
assert_contains 'origin_protocol_policy[[:space:]]*=[[:space:]]*"http-only"' "${FRONTEND_DIR}/main.tf" "Private CloudFront-to-ALB traffic must use the declared HTTP listener."
assert_contains 'vpc_origin_config' "${FRONTEND_DIR}/main.tf" "Distribution must reference the CloudFront VPC origin."
assert_contains 'data.aws_lb.backend_origin.internal' "${FRONTEND_DIR}/main.tf" "Terraform must reject an internet-facing ALB."
assert_contains 'load_balancer_type == "application"' "${FRONTEND_DIR}/main.tf" "Terraform must reject non-ALB origin resources."
assert_not_contains 'custom_origin_config' "${FRONTEND_DIR}/main.tf" "Public custom-origin routing must not remain."
assert_contains 'version[[:space:]]*=[[:space:]]*"~> 6\.0"' "${FRONTEND_DIR}/versions.tf" "AWS provider v6 is required for CloudFront VPC origin support."

cat >"${FIXTURE_DIR}/eks.json" <<'JSON'
{
  "cluster_name": {"value": "terraformers-dev-backend"},
  "aws_region": {"value": "ap-northeast-2"},
  "vpc_id": {"value": "vpc-0abcdef1234567890"},
  "load_balancer_controller_namespace": {"value": "kube-system"},
  "load_balancer_controller_service_account_name": {"value": "aws-load-balancer-controller"},
  "load_balancer_controller_irsa_role_arn": {"value": "arn:aws:iam::111122223333:role/terraformers-dev-load-balancer-controller"},
  "backend_origin_alb_security_group_id": {"value": "sg-0abcdef1234567890"}
}
JSON

python3 "${REPO_ROOT}/scripts/deploy/build-backend-origin-package.py" \
  --eks-outputs-json "${FIXTURE_DIR}/eks.json" \
  --template-dir "${TEMPLATE_DIR}" \
  --output-dir "${PACKAGE_DIR}"

for generated_file in \
  "${PACKAGE_DIR}/aws-load-balancer-controller-serviceaccount.yaml" \
  "${PACKAGE_DIR}/aws-load-balancer-controller-values.yaml" \
  "${PACKAGE_DIR}/backend-origin-ingress.yaml" \
  "${PACKAGE_DIR}/backend-origin-source-map.json" \
  "${PACKAGE_DIR}/package-summary.txt" \
  "${PACKAGE_DIR}/apply-order.txt"; do
  test -s "${generated_file}"
  assert_not_contains '__[A-Z0-9_]+__' "${generated_file}" "Generated backend origin package contains unresolved tokens."
done

assert_contains 'eks.amazonaws.com/role-arn:[[:space:]]*arn:aws:iam::111122223333:role/' "${PACKAGE_DIR}/aws-load-balancer-controller-serviceaccount.yaml" "Rendered controller ServiceAccount must carry IRSA."
assert_contains 'clusterName:[[:space:]]*terraformers-dev-backend' "${PACKAGE_DIR}/aws-load-balancer-controller-values.yaml" "Rendered controller values must target the EKS cluster."
assert_contains 'alb.ingress.kubernetes.io/security-groups:[[:space:]]*sg-0abcdef1234567890' "${PACKAGE_DIR}/backend-origin-ingress.yaml" "Rendered Ingress must use the Terraform-managed frontend security group."
assert_contains -- '--version 3\.4\.2' "${PACKAGE_DIR}/apply-order.txt" "Manual install boundary must pin controller chart 3.4.2."
assert_contains 'Supply the returned LoadBalancerArn as frontend-delivery.api_origin_load_balancer_arn' "${PACKAGE_DIR}/apply-order.txt" "ALB discovery must feed the frontend Terraform input."

printf '%s\n' \
  'backend_origin_contract=passed' \
  'load_balancer_controller_version=3.4.2' \
  'load_balancer_controller_identity=dedicated-irsa' \
  'load_balancer_scheme=internal' \
  'load_balancer_target_type=ip' \
  'load_balancer_ingress_source=cloudfront-managed-prefix-list' \
  'load_balancer_healthcheck=/actuator/health' \
  'listener_route=/api-prefix-only' \
  'cloudfront_origin_mode=vpc-origin' \
  'cloudfront_origin_protocol=HTTP-private' \
  'public_alb=false' \
  'actuator_listener_route=absent' \
  'controller_installation=required-not-performed' \
  'cluster_contact=none' \
  'aws_mutation=none' \
  >"${SUMMARY}"

cat "${SUMMARY}"
