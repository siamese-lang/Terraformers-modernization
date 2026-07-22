output "backend_image_repository_url" {
  description = "ECR repository URL for the backend image publish workflow."
  value       = aws_ecr_repository.backend.repository_url
}

output "backend_image_publisher_role_arn" {
  description = "Dedicated GitHub OIDC role ARN for publishing immutable backend images."
  value       = aws_iam_role.backend_image_publisher.arn
}

output "upload_bucket_name" {
  description = "S3 bucket name for uploaded architecture images."
  value       = aws_s3_bucket.uploads.bucket
}

output "upload_bucket_arn" {
  description = "S3 upload bucket ARN consumed by the EKS backend IRSA policy."
  value       = aws_s3_bucket.uploads.arn
}

output "result_bucket_name" {
  description = "S3 bucket name for generated analysis/Terraform result objects."
  value       = aws_s3_bucket.results.bucket
}

output "result_bucket_arn" {
  description = "S3 result bucket ARN consumed by the EKS backend IRSA policy."
  value       = aws_s3_bucket.results.arn
}

output "analysis_result_key_prefix" {
  description = "S3 key prefix for generated analysis results."
  value       = var.analysis_result_key_prefix
}

output "ai_log_queue_url" {
  description = "SQS queue URL available when the optional analysis publisher adapter is enabled."
  value       = aws_sqs_queue.ai_log.url
}

output "ai_log_queue_arn" {
  description = "SQS AI progress queue ARN consumed by the EKS backend IRSA policy."
  value       = aws_sqs_queue.ai_log.arn
}

output "terraform_log_queue_url" {
  description = "SQS queue URL available when the optional Terraform compatibility publisher is enabled."
  value       = aws_sqs_queue.terraform_log.url
}

output "terraform_log_queue_arn" {
  description = "SQS Terraform compatibility queue ARN consumed by the EKS backend IRSA policy."
  value       = aws_sqs_queue.terraform_log.arn
}

output "backend_runtime_secret_arn" {
  description = "Secrets Manager secret container ARN for backend runtime values."
  value       = aws_secretsmanager_secret.backend_runtime.arn
}

output "kubernetes_runtime_secret_name" {
  description = "Kubernetes Secret name expected by the backend base manifest."
  value       = "terraformers-backend-runtime-secrets"
}

output "next_required_runtime_values" {
  description = "Base production values that must be supplied by the stateful dependency and private secret-delivery layers. Optional adapter settings are intentionally excluded."
  value = [
    "SPRING_DATASOURCE_URL",
    "SPRING_DATASOURCE_USERNAME",
    "SPRING_DATASOURCE_PASSWORD",
    "COGNITO_REGION",
    "COGNITO_USER_POOL_ID",
    "COGNITO_USER_POOL_CLIENT_ID",
    "COGNITO_JWKS_URL"
  ]
}
