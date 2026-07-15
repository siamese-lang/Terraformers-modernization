variable "project_name" {
  description = "Project name used for resource names and tags."
  type        = string
  default     = "terraformers-modernization"
}

variable "environment" {
  description = "Deployment environment name used for resource names and tags."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for the runtime network."
  type        = string
  default     = "ap-northeast-2"
}

variable "common_tags" {
  description = "Common tags applied to runtime network resources."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR block for the Terraformers runtime VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "public_subnet_count" {
  description = "Number of public subnets to create."
  type        = number
  default     = 2

  validation {
    condition     = var.public_subnet_count >= 2
    error_message = "public_subnet_count must be at least 2 for load balancer and NAT placement options."
  }
}

variable "private_subnet_count" {
  description = "Number of private subnets to create."
  type        = number
  default     = 2

  validation {
    condition     = var.private_subnet_count >= 2
    error_message = "private_subnet_count must be at least 2 for EKS and RDS runtime validation."
  }
}

variable "subnet_newbits" {
  description = "Additional subnet bits passed to cidrsubnet when deriving public and private subnet CIDRs."
  type        = number
  default     = 4
}

variable "eks_cluster_name" {
  description = "EKS cluster name used for Kubernetes subnet discovery tags."
  type        = string
  default     = "terraformers-dev-backend"
}

variable "enable_nat_gateway" {
  description = "Create NAT gateway routes for private subnets. Keep false for low-cost static validation; enable for live EKS node egress when VPC endpoints are not enough."
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway shared by private route tables when enable_nat_gateway=true."
  type        = bool
  default     = true
}

variable "enable_s3_gateway_endpoint" {
  description = "Create an S3 gateway endpoint for private subnet route tables."
  type        = bool
  default     = true
}

variable "enable_bedrock_runtime_endpoint" {
  description = "Create an optional Bedrock Runtime interface endpoint. This only prepares network reachability and does not enable the Bedrock application adapter."
  type        = bool
  default     = false
}
