# Backend Analysis Adapter Design

## 1. Purpose

This document explains how the public modernization baseline replaces the original Python analysis runtime with Spring Boot backend-owned orchestration.

The goal is not to finish Bedrock or OpenSearch integration in one step. The goal is to make the backend own the analysis lifecycle and expose clear adapter boundaries for AWS dependencies.

## 2. Current backend-owned flow

```text
POST /api/analysis/jobs
  -> AnalysisJobService creates analysis_jobs row
  -> AnalysisJobOrchestrator moves status PENDING -> RUNNING
  -> AnalysisProvider analyzes the source object
  -> ProgressPublisher emits progress/result state
  -> analysis_jobs row moves RUNNING -> SUCCEEDED or FAILED
GET /api/analysis/jobs/{id}
  -> returns current RDB job state
```

## 3. Ports

### AnalysisProvider

`AnalysisProvider` is the boundary for Bedrock/OpenSearch-based Terraform draft generation.

Current implementation:

- `StubAnalysisProvider`
- returns deterministic Terraform draft text
- exists so Maven, Docker, API, RDB, and status transition can be verified before real Bedrock integration

Target implementation:

- reads uploaded object from S3 or receives object metadata from a storage adapter
- detects image media type
- invokes Bedrock vision model
- invokes embedding model
- queries OpenSearch/AOSS reference index
- returns generated Terraform draft and explanation

### ProgressPublisher

`ProgressPublisher` is the boundary for progress and result emission.

Current implementations:

- `LoggingProgressPublisher`: default local/CI-safe publisher
- `SqsProgressPublisher`: optional runtime adapter enabled by `terraformers.analysis.sqs-publisher-enabled=true`

This allows local build and tests to run without AWS credentials while keeping the production SQS boundary explicit.

## 4. Why this structure is preferable

The original Python service handled request orchestration, S3 read, Bedrock call, OpenSearch query, and SQS publish. These are important responsibilities, but they do not require Python by default.

By moving orchestration ownership to Spring Boot backend, the project can show:

- backend API contract
- RDB job lifecycle
- provider/adapter separation
- SQS progress boundary
- deployment-time runtime configuration
- failure state management
- smoke-testable backend behavior

## 5. Runtime properties

Production runtime config is injected through `application-prod.yml` and environment variables.

Important values:

- `BEDROCK_MODEL_ID`
- `BEDROCK_EMBEDDING_MODEL_ID`
- `OPENSEARCH_ENDPOINT`
- `INDEX_NAME`
- `VECTOR_FIELD_NAME`
- `CONTENT_FIELD_NAME`
- `AI_LOG_QUEUE_URL`
- `TERRAFORM_LOG_QUEUE_URL`
- `ANALYSIS_SQS_PUBLISHER_ENABLED`

Secret values must not be logged. Queue URLs and endpoints should be treated as runtime configuration and managed through Secrets Manager / External Secrets or repository environment variables depending on the deployment stage.

## 6. Next implementation steps

1. Add S3 object metadata/content reader port.
2. Add Bedrock provider implementation behind `AnalysisProvider`.
3. Add OpenSearch reference retriever port.
4. Persist generated result object key in `analysis_jobs.result_object_key`.
5. Add API smoke test for create/get analysis job.
6. Add runbook entries for Bedrock timeout, OpenSearch query failure, and SQS publish failure.
