variable "project_name" {
  description = "Project name used for network resource names and tags."
  type        = string
  default     = "terraformers"
}

variable "environment" {
  description = "Deployment environment name used for network resource names and tags."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for runtime network resources."
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the runtime validation VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use for public and private subnets."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2
    error_message = "az_count must be at least 2 for EKS and RDS subnet groups."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets. Provide at least az_count entries."
  type        = list(string)
  default     = ["10.40.0.0/24", "10.40.1.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "public_subnet_cidrs must contain at least two CIDR blocks."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private runtime subnets. Provide at least az_count entries."
  type        = list(string)
  default     = ["10.40.10.0/24", "10.40.11.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "private_subnet_cidrs must contain at least two CIDR blocks."
  }
}

variable "enable_nat_gateway" {
  description = "Create a single NAT gateway for private subnet internet egress. Disabled by default to keep live validation cost explicit."
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Create private VPC endpoints used by private EKS nodes for image pull and AWS API access."
  type        = bool
  default     = true
}

variable "interface_vpc_endpoint_services" {
  description = "AWS interface endpoint service suffixes to create when enable_vpc_endpoints is true."
  type        = list(string)
  default = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
    "sqs",
    "sts"
  ]
}

variable "common_tags" {
  description = "Additional tags applied to network resources."
  type        = map(string)
  default     = {}
}
