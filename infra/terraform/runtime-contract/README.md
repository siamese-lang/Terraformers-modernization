# Terraform Runtime Contract

## 1. Purpose

This directory defines the runtime values required by the Terraformers backend modernization baseline.

It is not yet a complete infrastructure stack. Its purpose is to keep the backend deployment contract explicit before importing or rebuilding the full Terraform environment.

## 2. Separation of config and secrets

`locals.tf` separates runtime values into two groups.

```text
backend_runtime_config
backend_runtime_secret_values
```

`backend_runtime_config` is suitable for Kubernetes ConfigMap values, such as feature flags and numeric limits.

`backend_runtime_secret_values` must be wired to a secret manager, External Secrets, Sealed Secrets, or CI/CD secret injection. Do not commit real values in `.tfvars`.

## 3. Adapter switches

The public baseline is safe by default.

```text
s3_reader_enabled              = false
s3_writer_enabled              = false
bedrock_provider_enabled       = false
bedrock_embedding_enabled      = false
opensearch_retriever_enabled   = false
analysis_sqs_publisher_enabled = false
```

Production runtime can enable adapters after AWS resources and IAM policies are ready.

```text
s3_reader_enabled              = true
s3_writer_enabled              = true
bedrock_provider_enabled       = true
bedrock_embedding_enabled      = true
opensearch_retriever_enabled   = true
analysis_sqs_publisher_enabled = true
```

## 4. Required backend environment keys

Non-secret config keys include:

- `SPRING_PROFILES_ACTIVE`
- `AWS_REGION`
- `S3_READER_ENABLED`
- `S3_WRITER_ENABLED`
- `BEDROCK_PROVIDER_ENABLED`
- `BEDROCK_EMBEDDING_ENABLED`
- `OPENSEARCH_RETRIEVER_ENABLED`
- `ANALYSIS_SQS_PUBLISHER_ENABLED`
- `BEDROCK_MAX_TOKENS`
- `OPENSEARCH_SERVICE_NAME`
- `OPENSEARCH_TOP_K`
- `ANALYSIS_RESULT_KEY_PREFIX`

Secret/runtime values include:

- `SPRING_DATASOURCE_URL`
- `SPRING_DATASOURCE_USERNAME`
- `SPRING_DATASOURCE_PASSWORD`
- `COGNITO_REGION`
- `COGNITO_USER_POOL_ID`
- `COGNITO_USER_POOL_CLIENT_ID`
- `COGNITO_JWKS_URL`
- `S3_BUCKET_NAME`
- `ANALYSIS_RESULT_BUCKET_NAME`
- `AI_LOG_QUEUE_URL`
- `TERRAFORM_LOG_QUEUE_URL`
- `BEDROCK_MODEL_ID`
- `BEDROCK_EMBEDDING_MODEL_ID`
- `OPENSEARCH_ENDPOINT`
- `INDEX_NAME`
- `VECTOR_FIELD_NAME`
- `CONTENT_FIELD_NAME`

## 5. Validation command

Use the example values only as a shape check.

```bash
cd infra/terraform/runtime-contract
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars.example
```

The example file contains placeholders only. It should not be applied to a real account as-is.
