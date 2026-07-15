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

output "backend_service_account_name" {
  description = "Kubernetes ServiceAccount name that should receive the IRSA annotation."
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
