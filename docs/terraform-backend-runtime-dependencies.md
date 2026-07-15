# Terraform Backend Runtime Dependencies

## 1. Purpose

This document describes the first Terraform scaffold for AWS resources required around the modernized Terraformers backend.

The goal is not to create the full production platform in one step. The goal is to separate the backend runtime dependencies that can be provisioned safely before EKS rollout:

```text
ECR repository
S3 upload bucket
S3 generated-result bucket
SQS AI progress queue
SQS Terraform-log compatibility queue
Secrets Manager runtime secret container
```

## 2. Terraform path

```text
infra/terraform/envs/backend-runtime-dependencies
```

## 3. What this Terraform creates

```text
aws_ecr_repository.backend
aws_ecr_lifecycle_policy.backend
aws_s3_bucket.uploads
aws_s3_bucket_public_access_block.uploads
aws_s3_bucket_versioning.uploads
aws_s3_bucket_server_side_encryption_configuration.uploads
aws_s3_bucket.results
aws_s3_bucket_public_access_block.results
aws_s3_bucket_versioning.results
aws_s3_bucket_server_side_encryption_configuration.results
aws_sqs_queue.ai_log
aws_sqs_queue.terraform_log
aws_secretsmanager_secret.backend_runtime
```

These resources correspond to the backend runtime and adapter boundaries already represented in code and Kubernetes manifests.

## 4. What this Terraform does not create

This scaffold intentionally excludes the following:

```text
VPC
EKS cluster
RDS MariaDB
Cognito user pool
OpenSearch/AOSS collection
Bedrock model access
IRSA role/policy binding
External Secrets controller
Kubernetes resources
Terraform apply/destroy product feature
```

Those should be added in separate PRs or connected to existing AWS resources with explicit validation gates.

## 5. Validation

Static validation:

```bash
bash scripts/checks/terraform-static-verification.sh
```

GitHub Actions:

```text
Terraform Static Verification
```

This validation runs `terraform init -backend=false`, `terraform fmt -check`, and `terraform validate` for:

```text
infra/terraform/runtime-contract
infra/terraform/envs/backend-runtime-dependencies
```

It does not run `terraform plan` or `terraform apply` for the AWS resource scaffold because that would require real credentials, globally unique bucket names, and an explicit cost-bearing environment decision.

## 6. Apply sequence when AWS is ready

Prepare an environment-specific tfvars file outside the repository:

```bash
cp infra/terraform/envs/backend-runtime-dependencies/terraform.tfvars.example /tmp/backend-runtime.tfvars
```

Edit the bucket names and tags, then run from the Terraform directory:

```bash
cd infra/terraform/envs/backend-runtime-dependencies
terraform init
terraform plan -var-file=/tmp/backend-runtime.tfvars
terraform apply -var-file=/tmp/backend-runtime.tfvars
```

After apply, capture these outputs:

```text
backend_image_repository_url
upload_bucket_name
result_bucket_name
ai_log_queue_url
terraform_log_queue_url
backend_runtime_secret_arn
```

Use them to complete the image publish workflow, runtime secret values, and environment-specific Kubernetes overlay.

## 7. Relationship to Kubernetes deployment

The outputs connect to Kubernetes as follows:

```text
backend_image_repository_url
  -> backend image publish workflow image_uri
  -> Kubernetes overlay image replacement

upload_bucket_name / result_bucket_name
  -> terraformers-backend-runtime-secrets
  -> S3_BUCKET_NAME / ANALYSIS_RESULT_BUCKET_NAME

ai_log_queue_url / terraform_log_queue_url
  -> terraformers-backend-runtime-secrets
  -> AI_LOG_QUEUE_URL / TERRAFORM_LOG_QUEUE_URL

backend_runtime_secret_arn
  -> source for external secret injection or manual secret population
```

## 8. Portfolio explanation

```text
Kubernetes에서 백엔드 컨테이너가 실제로 기동되는 경로를 확인한 뒤, AWS 배포에 필요한 주변 리소스를 Terraform으로 분리했습니다. 이 단계에서는 전체 EKS/RDS/Cognito까지 한 번에 만들지 않고, 백엔드 image publish와 S3/SQS/Secret 런타임 값에 필요한 ECR, S3, SQS, Secrets Manager부터 별도 검증 게이트로 관리했습니다. 이를 통해 배포 준비를 코드로 정리하되, 비용과 계정 의존성이 큰 리소스는 다음 단계로 분리했습니다.
```
