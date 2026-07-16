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
