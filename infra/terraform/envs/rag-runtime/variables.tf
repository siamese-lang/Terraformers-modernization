variable "aws_region" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment)) && length(var.environment) <= 10
    error_message = "environment must use lowercase letters, numbers, or hyphens and be at most 10 characters so AOSS names remain valid."
  }
}

variable "name_prefix" {
  type = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix)) && length(var.name_prefix) <= 12
    error_message = "name_prefix must start with a lowercase letter, use lowercase letters, numbers, or hyphens, and be at most 12 characters so AOSS names remain valid."
  }
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "eks_cluster_primary_security_group_id" {
  type = string
}

variable "backend_irsa_role_name" {
  type = string
}

variable "backend_irsa_role_arn" {
  type = string
}

variable "github_oidc_provider_arn" {
  type = string
}

variable "github_repository" {
  type    = string
  default = "siamese-lang/Terraformers-modernization"
}

variable "corpus_ingestion_environment" {
  type    = string
  default = "aws-rag-corpus-ingestion"
}

variable "corpus_bucket_name" {
  type = string
}

variable "corpus_prefix" {
  type    = string
  default = "terraformers-reference/v1/"
}

variable "tags" {
  type    = map(string)
  default = {}
}
