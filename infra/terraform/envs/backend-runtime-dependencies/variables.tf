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

variable "github_oidc_provider_arn" {
  description = "ARN of the existing GitHub Actions OIDC provider. This stage reuses the provider and does not create a duplicate."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn must identify the token.actions.githubusercontent.com OIDC provider."
  }
}

variable "github_repository" {
  description = "GitHub owner/repository allowed to publish the backend image."
  type        = string
  default     = "siamese-lang/Terraformers-modernization"

  validation {
    condition     = var.github_repository == "siamese-lang/Terraformers-modernization"
    error_message = "The backend image publisher trust must remain scoped to siamese-lang/Terraformers-modernization."
  }
}

variable "backend_image_publish_environment" {
  description = "GitHub Environment whose OIDC subject may assume the backend image publisher role."
  type        = string
  default     = "aws-backend-image-publish"

  validation {
    condition     = var.backend_image_publish_environment == "aws-backend-image-publish"
    error_message = "The backend image publisher must use the aws-backend-image-publish GitHub Environment."
  }
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
