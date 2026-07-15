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
  description = "AWS region for backend stateful dependencies."
  type        = string
  default     = "ap-northeast-2"
}

variable "common_tags" {
  description = "Common resource tags."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "Existing VPC ID where the private RDS security group should be created."
  type        = string
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs for the RDS subnet group. Use at least two subnets across availability zones for a real deployment."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "private_subnet_ids must include at least two subnet IDs."
  }
}

variable "allowed_app_security_group_ids" {
  description = "Security group IDs allowed to connect to MariaDB on port 3306, usually the EKS node or backend pod security group boundary."
  type        = list(string)
  default     = []
}

variable "allowed_database_cidr_blocks" {
  description = "Optional CIDR blocks allowed to connect to MariaDB on port 3306. Prefer security groups in real environments."
  type        = list(string)
  default     = []
}

variable "database_name" {
  description = "Application database name."
  type        = string
  default     = "terraformers"
}

variable "database_username" {
  description = "Application database username."
  type        = string
  default     = "terraformers_app"
}

variable "database_password" {
  description = "Application database password. Supply from a secure source such as GitHub Actions secret, tfvars outside git, or a secret manager workflow."
  type        = string
  sensitive   = true
}

variable "database_instance_class" {
  description = "RDS instance class for the MariaDB backend database."
  type        = string
  default     = "db.t4g.micro"
}

variable "database_allocated_storage_gb" {
  description = "Allocated RDS storage in GiB."
  type        = number
  default     = 20
}

variable "database_engine_version" {
  description = "MariaDB engine version."
  type        = string
  default     = "10.11"
}

variable "database_backup_retention_days" {
  description = "RDS backup retention period in days."
  type        = number
  default     = 1
}

variable "database_deletion_protection" {
  description = "Enable deletion protection for the RDS instance."
  type        = bool
  default     = false
}

variable "database_skip_final_snapshot" {
  description = "Skip final snapshot on RDS destroy. Keep true for disposable validation environments only."
  type        = bool
  default     = true
}

variable "cognito_deletion_protection" {
  description = "Enable deletion protection for the Cognito user pool."
  type        = bool
  default     = false
}
