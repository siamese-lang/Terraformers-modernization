output "cluster_name" {
  description = "EKS cluster name for kubectl and deployment workflows."
  value       = aws_eks_cluster.backend.name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = aws_eks_cluster.backend.endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data."
  value       = aws_eks_cluster.backend.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS control plane."
  value       = aws_security_group.eks_cluster.id
}

output "node_group_name" {
  description = "Backend node group name."
  value       = aws_eks_node_group.backend.node_group_name
}

output "node_role_arn" {
  description = "IAM role ARN attached to the backend managed node group."
  value       = aws_iam_role.eks_node.arn
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "vpc_id" {
  description = "Runtime VPC ID used by controller installation and backend origin validation."
  value       = var.vpc_id
}

output "backend_service_account_name" {
  description = "Kubernetes ServiceAccount name that should receive the backend IRSA annotation."
  value       = var.backend_service_account_name
}

output "backend_namespace" {
  description = "Kubernetes namespace for the backend service account."
  value       = var.backend_namespace
}

output "backend_irsa_role_arn" {
  description = "IAM role ARN to annotate on the backend Kubernetes ServiceAccount."
  value       = aws_iam_role.backend_irsa.arn
}

output "load_balancer_controller_namespace" {
  description = "Kubernetes namespace for AWS Load Balancer Controller."
  value       = var.load_balancer_controller_namespace
}

output "load_balancer_controller_service_account_name" {
  description = "Kubernetes ServiceAccount name for AWS Load Balancer Controller."
  value       = var.load_balancer_controller_service_account_name
}

output "load_balancer_controller_irsa_role_arn" {
  description = "IRSA role ARN for the pinned AWS Load Balancer Controller."
  value       = aws_iam_role.load_balancer_controller.arn
}

output "backend_origin_alb_security_group_id" {
  description = "Frontend security group for the private backend ALB."
  value       = aws_security_group.backend_origin_alb.id
}

output "cloudfront_origin_facing_prefix_list_id" {
  description = "AWS-managed CloudFront origin-facing prefix list allowed to reach the private backend ALB."
  value       = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
}

output "cluster_primary_security_group_id" {
  description = "AWS-managed primary security group ID for EKS cluster ENIs and private runtime integrations."
  value       = aws_eks_cluster.backend.vpc_config[0].cluster_security_group_id
}

output "backend_irsa_role_name" {
  description = "Name of the existing backend IRSA role for separately managed runtime policy attachments."
  value       = aws_iam_role.backend_irsa.name
}
