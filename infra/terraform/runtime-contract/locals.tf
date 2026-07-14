locals {
  backend_runtime_config = {
    SPRING_PROFILES_ACTIVE         = "prod"
    AWS_REGION                     = var.aws_region
    S3_READER_ENABLED              = tostring(var.adapter_switches.s3_reader_enabled)
    S3_WRITER_ENABLED              = tostring(var.adapter_switches.s3_writer_enabled)
    BEDROCK_PROVIDER_ENABLED       = tostring(var.adapter_switches.bedrock_provider_enabled)
    BEDROCK_EMBEDDING_ENABLED      = tostring(var.adapter_switches.bedrock_embedding_enabled)
    OPENSEARCH_RETRIEVER_ENABLED   = tostring(var.adapter_switches.opensearch_retriever_enabled)
    ANALYSIS_SQS_PUBLISHER_ENABLED = tostring(var.adapter_switches.analysis_sqs_publisher_enabled)
    BEDROCK_MAX_TOKENS             = tostring(var.bedrock_runtime.max_tokens)
    OPENSEARCH_SERVICE_NAME        = var.opensearch_runtime.service_name
    OPENSEARCH_TOP_K               = tostring(var.opensearch_runtime.top_k)
    ANALYSIS_RESULT_KEY_PREFIX     = var.object_storage_runtime.result_key_prefix
  }

  backend_runtime_secret_values = {
    SPRING_DATASOURCE_URL       = var.database_runtime.datasource_url
    SPRING_DATASOURCE_USERNAME  = var.database_runtime.datasource_username
    SPRING_DATASOURCE_PASSWORD  = var.database_runtime.datasource_password
    COGNITO_REGION              = var.cognito_runtime.region
    COGNITO_USER_POOL_ID        = var.cognito_runtime.user_pool_id
    COGNITO_USER_POOL_CLIENT_ID = var.cognito_runtime.user_pool_client_id
    COGNITO_JWKS_URL            = var.cognito_runtime.jwks_url
    S3_BUCKET_NAME              = var.object_storage_runtime.upload_bucket_name
    ANALYSIS_RESULT_BUCKET_NAME = var.object_storage_runtime.result_bucket_name
    AI_LOG_QUEUE_URL            = var.queue_runtime.ai_log_queue_url
    TERRAFORM_LOG_QUEUE_URL     = var.queue_runtime.terraform_log_queue_url
    BEDROCK_MODEL_ID            = var.bedrock_runtime.model_id
    BEDROCK_EMBEDDING_MODEL_ID  = var.bedrock_runtime.embedding_model_id
    OPENSEARCH_ENDPOINT         = var.opensearch_runtime.endpoint
    INDEX_NAME                  = var.opensearch_runtime.index_name
    VECTOR_FIELD_NAME           = var.opensearch_runtime.vector_field_name
    CONTENT_FIELD_NAME          = var.opensearch_runtime.content_field_name
  }
}
