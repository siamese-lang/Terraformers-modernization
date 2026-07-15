variable "environment" {
  description = "Environment name used for resource names and tags."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region where backend runtime dependency resources will be created."
  type        = string
  default     = "ap-northeast-2"
}

variable "name_prefix" {
  description = "Prefix used for named resources. Keep this short enough for AWS resource name limits."
  type        = string
  default     = "terraformers"
}

variable "tags" {
  description = "Additional tags applied to all supported AWS resources."
  type        = map(string)
  default     = {}
}

variable "backend_ecr_repository_name" {
  description = "ECR repository name for the Spring Boot backend image."
  type        = string
  default     = "terraformers-backend"
}

variable "upload_bucket_name" {
  description = "Globally unique S3 bucket name for uploaded architecture images. Must be environment-specific."
  type        = string
}

variable "result_bucket_name" {
  description = "Globally unique S3 bucket name for generated analysis/Terraform result objects. Must be environment-specific."
  type        = string
}

variable "analysis_result_key_prefix" {
  description = "S3 key prefix for generated analysis result objects."
  type        = string
  default     = "analysis-results"
}

variable "ai_log_queue_name" {
  description = "SQS queue name for AI analysis progress logs."
  type        = string
  default     = "terraformers-ai-log"
}

variable "terraform_log_queue_name" {
  description = "SQS queue name for Terraform progress/result logs. Kept for original runtime contract compatibility; this project does not expose Terraform run/apply/destroy APIs."
  type        = string
  default     = "terraformers-terraform-log"
}

variable "runtime_secret_name" {
  description = "Secrets Manager secret container name for backend runtime values. This Terraform does not write secret values."
  type        = string
  default     = "terraformers/dev/backend/runtime"
}
