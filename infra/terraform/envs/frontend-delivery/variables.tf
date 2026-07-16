variable "environment" {
  description = "Deployment environment used for names and tags."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for the frontend S3 bucket. CloudFront remains global."
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

variable "api_origin_domain_name" {
  description = "DNS name of the approved HTTPS backend origin. Supply only a hostname, without scheme or path."
  type        = string

  validation {
    condition = (
      length(trimspace(var.api_origin_domain_name)) > 0 &&
      !can(regex("://", var.api_origin_domain_name)) &&
      !can(regex("/", var.api_origin_domain_name))
    )
    error_message = "api_origin_domain_name must be a hostname without scheme or path."
  }
}

variable "api_origin_protocol_policy" {
  description = "CloudFront protocol policy for the backend origin."
  type        = string
  default     = "https-only"

  validation {
    condition     = contains(["https-only", "match-viewer"], var.api_origin_protocol_policy)
    error_message = "api_origin_protocol_policy must be https-only or match-viewer."
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

  validation {
    condition     = length(var.aliases) == 0 || (var.acm_certificate_arn != null && length(trimspace(var.acm_certificate_arn)) > 0)
    error_message = "acm_certificate_arn is required when aliases are configured."
  }
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
