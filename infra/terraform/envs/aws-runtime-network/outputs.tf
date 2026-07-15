output "vpc_id" {
  description = "Runtime VPC ID for EKS, RDS, and backend runtime dependencies."
  value       = aws_vpc.runtime.id
}

output "vpc_cidr_block" {
  description = "Runtime VPC CIDR block."
  value       = aws_vpc.runtime.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs tagged for Kubernetes public load balancers."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs tagged for EKS, RDS, and internal load balancers."
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidr_blocks" {
  description = "Private subnet CIDR blocks for controlled RDS ingress planning when security-group references are not yet available."
  value       = aws_subnet.private[*].cidr_block
}

output "private_route_table_ids" {
  description = "Private route table IDs used by VPC endpoints."
  value       = aws_route_table.private[*].id
}

output "s3_gateway_endpoint_id" {
  description = "S3 gateway endpoint ID when enabled."
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "bedrock_runtime_endpoint_dns_name" {
  description = "Optional Bedrock Runtime interface endpoint DNS name when enabled."
  value       = try(aws_vpc_endpoint.bedrock_runtime[0].dns_entry[0].dns_name, null)
}
