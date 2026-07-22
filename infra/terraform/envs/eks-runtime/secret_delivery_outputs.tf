output "aws_region" {
  description = "AWS region used by the EKS runtime and Secrets Manager provider."
  value       = var.aws_region
}

output "external_secrets_service_account_name" {
  description = "Dedicated Kubernetes ServiceAccount name used by External Secrets."
  value       = var.external_secrets_service_account_name
}

output "external_secrets_irsa_role_arn" {
  description = "IAM role ARN for the dedicated External Secrets Kubernetes ServiceAccount."
  value       = aws_iam_role.external_secrets_irsa.arn
}
