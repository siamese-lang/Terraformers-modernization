output "backend_image_repository_url" {
  description = "ECR repository URL for the backend image publish workflow."
  value       = aws_ecr_repository.backend.repository_url
}

output "upload_bucket_name" {
  description = "S3 bucket name for uploaded architecture images."
  value       = aws_s3_bucket.uploads.bucket
}

output "result_bucket_name" {
  description = "S3 bucket name for generated analysis/Terraform result objects."
  value       = aws_s3_bucket.results.bucket
}

output "analysis_result_key_prefix" {
  description = "S3 key prefix for generated analysis results."
  value       = var.analysis_result_key_prefix
}

output "ai_log_queue_url" {
  description = "SQS queue URL for AI analysis progress logs."
  value       = aws_sqs_queue.ai_log.url
}

output "terraform_log_queue_url" {
  description = "SQS queue URL for Terraform progress/result log compatibility."
  value       = aws_sqs_queue.terraform_log.url
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
  description = "Runtime values still required before the prod Kubernetes overlay can start the backend."
  value = [
    "SPRING_DATASOURCE_URL",
    "SPRING_DATASOURCE_USERNAME",
    "SPRING_DATASOURCE_PASSWORD",
    "COGNITO_REGION",
    "COGNITO_USER_POOL_ID",
    "COGNITO_USER_POOL_CLIENT_ID",
    "COGNITO_JWKS_URL",
    "BEDROCK_MODEL_ID",
    "BEDROCK_EMBEDDING_MODEL_ID",
    "OPENSEARCH_ENDPOINT",
    "INDEX_NAME",
    "VECTOR_FIELD_NAME",
    "CONTENT_FIELD_NAME"
  ]
}
