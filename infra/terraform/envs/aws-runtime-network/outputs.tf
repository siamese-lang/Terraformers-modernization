output "vpc_id" {
  description = "VPC ID for backend-stateful-dependencies and eks-runtime."
  value       = aws_vpc.runtime.id
}

output "vpc_cidr_block" {
  description = "Runtime VPC CIDR block."
  value       = aws_vpc.runtime.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs. These are available for later ALB or NAT work, not used for the first private smoke by default."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for backend-stateful-dependencies and eks-runtime."
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidr_blocks" {
  description = "Private subnet CIDRs that can be used as an initial RDS allowlist for disposable live validation."
  value       = aws_subnet.private[*].cidr_block
}

output "eks_cluster_name_hint" {
  description = "Expected EKS cluster name when eks-runtime uses the same project_name and environment."
  value       = local.eks_cluster_name
}

output "nat_gateway_enabled" {
  description = "Whether this network created a NAT gateway."
  value       = var.enable_nat_gateway
}

output "nat_gateway_id" {
  description = "NAT gateway ID when enable_nat_gateway is true."
  value       = var.enable_nat_gateway ? aws_nat_gateway.private_egress[0].id : null
}

output "vpc_endpoints_enabled" {
  description = "Whether this network created private VPC endpoints."
  value       = var.enable_vpc_endpoints
}

output "interface_vpc_endpoint_security_group_id" {
  description = "Security group ID attached to interface VPC endpoints when enabled."
  value       = var.enable_vpc_endpoints ? aws_security_group.interface_endpoints[0].id : null
}

output "interface_vpc_endpoint_ids" {
  description = "Interface VPC endpoint IDs keyed by full AWS service name."
  value = {
    for service_name, endpoint in aws_vpc_endpoint.interface : service_name => endpoint.id
  }
}

output "s3_gateway_vpc_endpoint_id" {
  description = "S3 gateway VPC endpoint ID when enabled."
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.s3[0].id : null
}
