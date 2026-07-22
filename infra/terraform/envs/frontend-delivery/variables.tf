variable "environment" {
  description = "Deployment environment used for names and tags."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for the frontend S3 bucket and private backend ALB. CloudFront remains global."
  type        = string
  default     = "ap-northeast-2"
}

variable "name_prefix" {
  description = "Prefix used for named frontend delivery resources."
  type        = string
  default     = "terraformers"
}

variable "tags" {
  description = "Additional tags applied to supported resources."
  type        = map(string)
  default     = {}
}

variable "frontend_bucket_name" {
  description = "Globally unique private S3 bucket name for the React production bundle."
  type        = string

  validation {
    condition = (
      length(var.frontend_bucket_name) >= 3 &&
      length(var.frontend_bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.frontend_bucket_name))
    )
    error_message = "frontend_bucket_name must be a valid lowercase S3 bucket name."
  }
}

variable "frontend_bucket_force_destroy" {
  description = "Whether Terraform may delete a non-empty frontend bucket. Keep false for real environments."
  type        = bool
  default     = false
}

variable "noncurrent_version_expiration_days" {
  description = "Days to retain noncurrent frontend object versions for rollback."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_expiration_days >= 7
    error_message = "Retain at least seven days of noncurrent frontend object versions."
  }
}

variable "api_origin_load_balancer_arn" {
  description = "ARN of the controller-created internal Application Load Balancer used as the CloudFront VPC origin."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:loadbalancer/app/", var.api_origin_load_balancer_arn))
    error_message = "api_origin_load_balancer_arn must be an Application Load Balancer ARN."
  }
}

variable "aliases" {
  description = "Optional custom frontend domains for the CloudFront distribution."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "Optional us-east-1 ACM certificate ARN required when aliases are configured."
  type        = string
  default     = null
  nullable    = true
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_200 includes major Asia edge locations."
  type        = string
  default     = "PriceClass_200"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be a valid CloudFront price class."
  }
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions token.actions.githubusercontent.com IAM OIDC provider ARN from the live foundation state. This environment reuses it and never creates a duplicate provider."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn must identify the existing token.actions.githubusercontent.com provider."
  }
}

variable "github_repository" {
  description = "GitHub owner/repository allowed to assume the frontend delivery role."
  type        = string
  default     = "siamese-lang/Terraformers-modernization"

  validation {
    condition     = var.github_repository == "siamese-lang/Terraformers-modernization"
    error_message = "github_repository must remain the exact Terraformers-modernization repository unless this contract is intentionally updated."
  }
}

variable "github_environment" {
  description = "GitHub Environment name allowed in the frontend delivery OIDC subject."
  type        = string
  default     = "frontend-delivery"

  validation {
    condition     = var.github_environment == "frontend-delivery"
    error_message = "github_environment must remain frontend-delivery for the guarded delivery workflow."
  }
}

variable "frontend_delivery_role_name" {
  description = "Optional explicit IAM role name for GitHub OIDC frontend delivery. Defaults to the frontend delivery resource prefix."
  type        = string
  default     = null
  nullable    = true
}
