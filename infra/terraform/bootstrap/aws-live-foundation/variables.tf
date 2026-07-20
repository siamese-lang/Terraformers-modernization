variable "aws_region" {
  description = "AWS region for the Terraform state bucket. IAM resources are global."
  type        = string
  default     = "ap-northeast-2"
}

variable "expected_aws_account_id" {
  description = "Exact 12-digit AWS account ID allowed for the live foundation bootstrap."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_aws_account_id))
    error_message = "expected_aws_account_id must be exactly 12 digits."
  }
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

variable "apply_role_name" {
  description = "IAM role name assumed by the protected GitHub environment for approved Terraform applies."
  type        = string
  default     = "terraformers-live-terraform-apply"
}

variable "apply_github_environment" {
  description = "Protected GitHub environment allowed to assume the live Terraform apply role."
  type        = string
  default     = "aws-live-apply"

  validation {
    condition     = length(trimspace(var.apply_github_environment)) > 0 && !strcontains(var.apply_github_environment, "*")
    error_message = "apply_github_environment must not be empty or contain '*'."
  }
}

variable "approved_apply_iam_policy_arn" {
  description = "Exact customer-managed IAM policy ARN that the approved apply workflow may update."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/.+$", var.approved_apply_iam_policy_arn))
    error_message = "approved_apply_iam_policy_arn must be a customer-managed IAM policy ARN."
  }
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

variable "rag_runtime_corpus_bucket_name" {
  description = "Exact corpus bucket the approved rag-runtime apply may create and configure."
  type        = string
  default     = "terraformers-dev-rag-corpus-024863981627"

  validation {
    condition     = var.rag_runtime_corpus_bucket_name == "terraformers-dev-rag-corpus-024863981627"
    error_message = "rag_runtime_corpus_bucket_name must be terraformers-dev-rag-corpus-024863981627."
  }
}

variable "rag_runtime_vpc_id" {
  description = "Exact VPC ID in which the approved rag-runtime security groups may be created."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.rag_runtime_vpc_id))
    error_message = "rag_runtime_vpc_id must be a VPC ID."
  }
}
