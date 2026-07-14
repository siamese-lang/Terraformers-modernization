# Backend Analysis Adapter Design

## 1. Purpose

This document explains how the public modernization baseline replaces the original Python analysis runtime with Spring Boot backend-owned orchestration.

The goal is not to finish every AWS integration in one step. The goal is to make the backend own the analysis lifecycle and expose clear adapter boundaries for AWS dependencies.

## 2. Current backend-owned flow

```text
POST /api/analysis/jobs
  -> AnalysisJobService creates analysis_jobs row
  -> AnalysisJobOrchestrator moves status PENDING -> RUNNING
  -> ObjectReader checks the uploaded S3 object boundary
  -> ReferenceRetriever returns reference patterns
  -> AnalysisProvider analyzes the source object
  -> ProgressPublisher emits progress/result state
  -> analysis_jobs row moves RUNNING -> SUCCEEDED or FAILED
GET /api/analysis/jobs/{id}
  -> returns current RDB job state
```

## 3. Ports

### ObjectReader

`ObjectReader` is the boundary for reading uploaded image objects.

Current implementations:

- `StubObjectReader`: default local/CI-safe object reader. It infers a content type from the object key and does not require AWS credentials.
- `AwsS3ObjectReader`: optional production adapter enabled by `terraformers.storage.s3-reader-enabled=true`.

Target responsibility:

- verify bucket/key reachability;
- read object metadata such as content type, content length, and ETag;
- read object bytes when Bedrock vision integration needs base64 image payload;
- fail clearly on missing object or access denial.

### EmbeddingProvider

`EmbeddingProvider` is the boundary for turning retrieval text into an embedding vector.

Current implementations:

- `StubEmbeddingProvider`: default local/CI-safe deterministic vector provider.
- `BedrockEmbeddingProvider`: optional production adapter enabled by `terraformers.analysis.bedrock-embedding-enabled=true`.

This keeps OpenSearch reference retrieval testable without model calls while still exposing the real Bedrock embedding path for deployment.

### ReferenceRetriever

`ReferenceRetriever` is the boundary for retrieving reference patterns before Terraform draft generation.

Current implementations:

- `StubReferenceRetriever`
  - returns deterministic reference documents for local/CI verification;
  - allows `AnalysisProvider` tests to verify the reference retrieval step without OpenSearch credentials.

- `OpenSearchReferenceRetriever`
  - optional production adapter enabled by `terraformers.analysis.opensearch-retriever-enabled=true`;
  - uses `EmbeddingProvider` to build a vector;
  - builds an OpenSearch k-NN query with `OpenSearchKnnQueryBuilder`;
  - sends a SigV4 signed request with `SignedOpenSearchHttpClient`;
  - parses ranked reference documents with `OpenSearchResponseParser`.

Operational boundary:

```text
Local/CI default: StubEmbeddingProvider + StubReferenceRetriever
Production optional: BedrockEmbeddingProvider + OpenSearchReferenceRetriever
```

Target responsibility:

- build an embedding request from image analysis text or detected service names;
- invoke Bedrock embedding model;
- query OpenSearch/AOSS k-NN index;
- return ranked reference documents;
- fail clearly on missing index, wrong vector field, access denial, or timeout.

### AnalysisProvider

`AnalysisProvider` is the boundary for Terraform draft generation.

Current implementations:

- `StubAnalysisProvider`
  - default local/CI-safe provider;
  - reads source object metadata through `ObjectReader`;
  - retrieves reference patterns through `ReferenceRetriever`;
  - returns deterministic Terraform draft text;
  - exists so Maven, Docker, API, RDB, storage boundary, reference boundary, and status transition can be verified without AWS model calls.

- `BedrockAnalysisProvider`
  - optional production adapter enabled by `terraformers.analysis.bedrock-provider-enabled=true`;
  - reads uploaded object content through `ObjectReader`;
  - builds a Claude vision request through `BedrockPromptBuilder`;
  - invokes Bedrock Runtime through AWS SDK v2;
  - parses returned Terraform HCL through `BedrockResponseParser`;
  - keeps Bedrock call logic inside backend-owned orchestration rather than a Python side service.

Important boundary:

```text
Local/CI default: StubObjectReader + StubReferenceRetriever + StubAnalysisProvider
Production optional: AwsS3ObjectReader + OpenSearchReferenceRetriever + BedrockAnalysisProvider
```

This keeps CI deterministic and credential-free while making the production adapter path explicit.

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
- S3 object access boundary
- embedding generation boundary
- reference retrieval boundary
- Bedrock invocation boundary
- SQS progress boundary
- deployment-time runtime configuration
- failure state management
- smoke-testable backend behavior

## 5. Runtime properties

Production runtime config is injected through `application-prod.yml` and environment variables.

Important values:

- `S3_READER_ENABLED`
- `BEDROCK_PROVIDER_ENABLED`
- `BEDROCK_EMBEDDING_ENABLED`
- `BEDROCK_MODEL_ID`
- `BEDROCK_EMBEDDING_MODEL_ID`
- `BEDROCK_MAX_TOKENS`
- `OPENSEARCH_RETRIEVER_ENABLED`
- `OPENSEARCH_ENDPOINT`
- `OPENSEARCH_SERVICE_NAME`
- `OPENSEARCH_TOP_K`
- `INDEX_NAME`
- `VECTOR_FIELD_NAME`
- `CONTENT_FIELD_NAME`
- `AI_LOG_QUEUE_URL`
- `TERRAFORM_LOG_QUEUE_URL`
- `ANALYSIS_SQS_PUBLISHER_ENABLED`

Secret values must not be logged. Queue URLs and endpoints should be treated as runtime configuration and managed through Secrets Manager / External Secrets or repository environment variables depending on the deployment stage.

## 6. Current completion boundary

Implemented in the public baseline:

- backend-owned analysis job API
- RDB job lifecycle
- S3 object reader port and optional S3 adapter
- embedding provider port and optional Bedrock embedding adapter
- reference retrieval port, stub retriever, and optional SigV4-signed OpenSearch/AOSS retriever
- Bedrock provider boundary and optional Bedrock Runtime adapter
- SQS progress publisher boundary and optional SQS adapter
- local/CI-safe stub path

Not yet complete:

- persistence of generated Terraform object to S3
- full browser E2E validation
- deployed AWS evidence

## 7. Next implementation steps

1. Persist generated Terraform result object key in `analysis_jobs.result_object_key`.
2. Add API smoke test assertions for `SUCCEEDED` and result preview.
3. Add runbook entries for S3 object missing, S3 access denied, Bedrock timeout, OpenSearch query failure, and SQS publish failure.
