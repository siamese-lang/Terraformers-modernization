variable "aws_region" {
  description = "AWS region for the Terraform state bucket. IAM resources are global."
  type        = string
  default     = "ap-northeast-2"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state and native lock files."
  type        = string

  validation {
    condition = (
      length(var.state_bucket_name) >= 3 &&
      length(var.state_bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.state_bucket_name))
    )
    error_message = "state_bucket_name must be a valid lowercase S3 bucket name."
  }
}

variable "state_prefix" {
  description = "S3 prefix containing stage-specific Terraform state and .tflock objects."
  type        = string
  default     = "terraformers-modernization/dev"

  validation {
    condition     = length(trim(var.state_prefix, "/")) > 0
    error_message = "state_prefix must not be empty."
  }
}

variable "github_repository" {
  description = "GitHub repository in owner/name form."
  type        = string
  default     = "siamese-lang/Terraformers-modernization"
}

variable "github_environment" {
  description = "Protected GitHub environment allowed to assume the live Terraform plan role."
  type        = string
  default     = "aws-live-plan"
}

variable "github_oidc_subjects" {
  description = "Exact GitHub OIDC subject claims allowed to assume the plan role. Do not use wildcards."
  type        = list(string)
  default = [
    "repo:siamese-lang/Terraformers-modernization:environment:aws-live-plan"
  ]

  validation {
    condition = (
      length(var.github_oidc_subjects) > 0 &&
      alltrue([
        for subject in var.github_oidc_subjects :
        length(subject) > 0 && !strcontains(subject, "*")
      ])
    )
    error_message = "github_oidc_subjects must contain exact non-wildcard subject claims."
  }
}

variable "existing_github_oidc_provider_arn" {
  description = "Existing token.actions.githubusercontent.com IAM OIDC provider ARN. Leave null to create it."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.existing_github_oidc_provider_arn == null ||
      can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.existing_github_oidc_provider_arn))
    )
    error_message = "existing_github_oidc_provider_arn must reference token.actions.githubusercontent.com."
  }
}

variable "plan_role_name" {
  description = "IAM role name assumed by the protected GitHub environment for read-only Terraform plans."
  type        = string
  default     = "terraformers-live-terraform-plan"
}

variable "common_tags" {
  description = "Tags applied to supported bootstrap resources."
  type        = map(string)
  default = {
    Project     = "terraformers-modernization"
    Environment = "dev"
    ManagedBy   = "terraform-bootstrap"
  }
}
