variable "project_name" {
  description = "Project name used for naming and tagging."
  type        = string
  default     = "terraformers"
}

variable "environment" {
  description = "Deployment environment name used for naming and tagging."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for EKS runtime resources."
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_id" {
  description = "Existing VPC ID where the EKS cluster and worker nodes will run."
  type        = string
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs for EKS control plane networking and node groups."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least two private subnet IDs are required for a usable EKS runtime."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.30"
}

variable "cluster_endpoint_public_access" {
  description = "Whether to expose the EKS API endpoint publicly. Prefer false when private network access is available."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR allowlist for the public EKS API endpoint. Use a narrow operator CIDR, not 0.0.0.0/0, for real environments."
  type        = list(string)
  default     = ["203.0.113.10/32"]
}

variable "enabled_cluster_log_types" {
  description = "EKS control-plane log types to enable."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "node_instance_types" {
  description = "EC2 instance types for the backend node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_disk_size" {
  description = "Worker node disk size in GiB."
  type        = number
  default     = 20
}

variable "node_labels" {
  description = "Labels applied to the managed backend node group."
  type        = map(string)
  default = {
    role = "backend-runtime"
  }
}

variable "node_desired_size" {
  description = "Desired backend node count."
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum backend node count."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum backend node count."
  type        = number
  default     = 2
}

variable "backend_namespace" {
  description = "Kubernetes namespace where the backend service account will exist."
  type        = string
  default     = "terraformers-runtime"
}

variable "backend_service_account_name" {
  description = "Kubernetes ServiceAccount name used by the backend Deployment."
  type        = string
  default     = "terraformers-backend"
}

variable "upload_bucket_arn" {
  description = "S3 upload bucket ARN from backend-runtime-dependencies."
  type        = string
}

variable "result_bucket_arn" {
  description = "S3 generated-result bucket ARN from backend-runtime-dependencies."
  type        = string
}

variable "ai_log_queue_arn" {
  description = "SQS AI progress queue ARN from backend-runtime-dependencies."
  type        = string
}

variable "terraform_log_queue_arn" {
  description = "SQS Terraform-log compatibility queue ARN from backend-runtime-dependencies."
  type        = string
}

variable "backend_runtime_secret_arn" {
  description = "Secrets Manager backend runtime secret ARN from backend-runtime-dependencies."
  type        = string
}

variable "bedrock_model_resource_arns" {
  description = "Optional Bedrock model ARNs the backend may invoke when the Bedrock adapter is enabled. Keep empty until model access is intentionally validated."
  type        = list(string)
  default     = []
}
