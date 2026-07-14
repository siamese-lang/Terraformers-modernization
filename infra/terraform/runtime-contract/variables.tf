variable "environment" {
  description = "Deployment environment name used for naming and tagging."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for runtime adapters."
  type        = string
  default     = "ap-northeast-2"
}

variable "adapter_switches" {
  description = "Backend analysis adapter switches. Keep disabled until each AWS dependency is provisioned and validated."
  type = object({
    s3_reader_enabled             = bool
    s3_writer_enabled             = bool
    bedrock_provider_enabled      = bool
    bedrock_embedding_enabled     = bool
    opensearch_retriever_enabled  = bool
    analysis_sqs_publisher_enabled = bool
  })
  default = {
    s3_reader_enabled              = false
    s3_writer_enabled              = false
    bedrock_provider_enabled       = false
    bedrock_embedding_enabled      = false
    opensearch_retriever_enabled   = false
    analysis_sqs_publisher_enabled = false
  }
}

variable "database_runtime" {
  description = "Database runtime connection values. Values must be supplied from a secure source, not committed tfvars."
  type = object({
    datasource_url      = string
    datasource_username = string
    datasource_password = string
  })
  sensitive = true
}

variable "cognito_runtime" {
  description = "Cognito runtime values consumed by the backend."
  type = object({
    region              = string
    user_pool_id        = string
    user_pool_client_id = string
    jwks_url            = string
  })
}

variable "object_storage_runtime" {
  description = "Upload and generated-result object storage runtime values."
  type = object({
    upload_bucket_name  = string
    result_bucket_name  = string
    result_key_prefix   = string
  })
}

variable "queue_runtime" {
  description = "SQS runtime values for progress and Terraform result channels."
  type = object({
    ai_log_queue_url        = string
    terraform_log_queue_url = string
  })
}

variable "bedrock_runtime" {
  description = "Bedrock runtime values for vision generation and embedding."
  type = object({
    model_id           = string
    embedding_model_id = string
    max_tokens         = number
  })
}

variable "opensearch_runtime" {
  description = "OpenSearch/AOSS runtime values for reference retrieval."
  type = object({
    endpoint          = string
    service_name      = string
    top_k             = number
    index_name        = string
    vector_field_name = string
    content_field_name = string
  })
}
