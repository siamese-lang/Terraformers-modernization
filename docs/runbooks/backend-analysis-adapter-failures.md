# Backend Analysis Adapter Failure Runbook

## 1. Purpose

This runbook explains how to triage failures in the backend-owned analysis job flow.

The goal is to avoid treating every failed analysis job as an AI model problem. The backend flow has multiple adapter boundaries, and each boundary should be checked separately.

```text
POST /api/analysis/jobs
  -> RDB analysis_jobs row
  -> ObjectReader
  -> ReferenceRetriever
  -> AnalysisProvider
  -> ObjectWriter
  -> ProgressPublisher
  -> GET /api/analysis/jobs/{id}
```

## 2. First check: job state

Fetch the job state through the API.

```bash
BASE_URL=http://localhost:8080
JOB_ID=<analysis-job-id>

curl -sS "${BASE_URL}/api/analysis/jobs/${JOB_ID}" | python3 -m json.tool
```

Expected success shape:

```json
{
  "status": "SUCCEEDED",
  "provider": "stub-integrated-java",
  "resultObjectKey": "analysis-results/project-smoke/2026/07/14/<job-id>/main.tf",
  "resultPreview": "terraform { ... }",
  "failureReason": null
}
```

Failure shape:

```json
{
  "status": "FAILED",
  "provider": null,
  "resultObjectKey": null,
  "resultPreview": null,
  "failureReason": "..."
}
```

The `failureReason` should be mapped to the adapter boundary below.

## 3. Adapter failure map

| Symptom | Likely boundary | Primary check |
| --- | --- | --- |
| HTTP 400 on job creation | API request validation | `projectId`, `sourceBucket`, `sourceKey` request fields |
| Job remains missing | RDB persistence | datasource config, Flyway migration, repository logs |
| `NoSuchKey`, 404, or object not found | `ObjectReader` | uploaded image key and bucket |
| S3 access denied during read | `ObjectReader` | runtime role has `s3:GetObject` and `s3:HeadObject` |
| Unsupported image content type | `AnalysisProvider` prompt build | source object `Content-Type` |
| Bedrock timeout or invoke failure | `AnalysisProvider` | model id, region, IAM, request size, timeout |
| Embedding response missing vector | `EmbeddingProvider` | embedding model id and response format |
| OpenSearch HTTP 403 | `ReferenceRetriever` | SigV4 service name, IAM policy, AOSS access policy |
| OpenSearch HTTP 404 | `ReferenceRetriever` | endpoint, index name, path normalization |
| Wrong vector field or empty result | `ReferenceRetriever` | `VECTOR_FIELD_NAME`, `CONTENT_FIELD_NAME`, index mapping |
| S3 result write failure | `ObjectWriter` | bucket, prefix policy, `s3:PutObject` permission |
| Job succeeds but progress is not visible | `ProgressPublisher` | SQS queue URL, `sqs:SendMessage`, frontend polling path |

## 4. Runtime switch checklist

Local/CI default path should not call AWS:

```text
S3_READER_ENABLED=false
S3_WRITER_ENABLED=false
BEDROCK_PROVIDER_ENABLED=false
BEDROCK_EMBEDDING_ENABLED=false
OPENSEARCH_RETRIEVER_ENABLED=false
ANALYSIS_SQS_PUBLISHER_ENABLED=false
```

Production adapter path:

```text
S3_READER_ENABLED=true
S3_WRITER_ENABLED=true
BEDROCK_PROVIDER_ENABLED=true
BEDROCK_EMBEDDING_ENABLED=true
OPENSEARCH_RETRIEVER_ENABLED=true
ANALYSIS_SQS_PUBLISHER_ENABLED=true
```

If production fails but local smoke succeeds, compare these switches first.

## 5. S3 source object failures

### Symptoms

- job status is `FAILED`;
- `failureReason` mentions S3 read, object not found, access denied, or unsupported content type;
- no `resultObjectKey` is recorded.

### Checks

Confirm the source bucket/key sent to the API.

```bash
curl -sS "${BASE_URL}/api/analysis/jobs/${JOB_ID}" | python3 -m json.tool
```

Then check the object out-of-band.

```bash
aws s3api head-object \
  --bucket <source-bucket> \
  --key <source-key>
```

Expected:

- object exists;
- `ContentType` is one of `image/png`, `image/jpeg`, `image/webp`, or `image/gif`;
- runtime role can call `s3:HeadObject` and `s3:GetObject`.

### Common fixes

- correct the source key stored by upload API;
- preserve content type when uploading images;
- grant `s3:GetObject` and `s3:HeadObject` to the backend runtime role;
- ensure bucket policy allows the backend role and prefix.

## 6. Bedrock provider failures

### Symptoms

- job status is `FAILED`;
- `failureReason` mentions model id, Bedrock invoke, timeout, or unsupported media type;
- S3 source object checks pass.

### Checks

Verify runtime config:

```text
BEDROCK_PROVIDER_ENABLED=true
BEDROCK_MODEL_ID=<vision-capable-model-id>
BEDROCK_MAX_TOKENS=4096
AWS_REGION=<deployment-region>
```

Check application logs around the job id.

```bash
kubectl logs deploy/terraformers-backend --since=30m | grep "<analysis-job-id>"
```

Expected:

- request reached `BedrockAnalysisProvider`;
- prompt builder accepted the image content type;
- model id is configured;
- IAM role can call Bedrock Runtime.

### Common fixes

- set the correct `BEDROCK_MODEL_ID`;
- reduce image size if request payload is too large;
- adjust timeout/retry settings if Bedrock call is slow;
- grant the backend role permission to invoke the configured model.

## 7. OpenSearch/AOSS reference retrieval failures

### Symptoms

- job status is `FAILED` when `OPENSEARCH_RETRIEVER_ENABLED=true`;
- failure mentions OpenSearch HTTP status, index, vector field, or embedding;
- local stub path succeeds.

### Checks

Verify runtime config:

```text
BEDROCK_EMBEDDING_ENABLED=true
BEDROCK_EMBEDDING_MODEL_ID=<embedding-model-id>
OPENSEARCH_RETRIEVER_ENABLED=true
OPENSEARCH_ENDPOINT=<endpoint>
OPENSEARCH_SERVICE_NAME=aoss
INDEX_NAME=<reference-index>
VECTOR_FIELD_NAME=<vector-field>
CONTENT_FIELD_NAME=<content-field>
OPENSEARCH_TOP_K=3
```

Use `OPENSEARCH_SERVICE_NAME=aoss` for OpenSearch Serverless / AOSS and `OPENSEARCH_SERVICE_NAME=es` only if the deployment uses a classic OpenSearch domain that requires that signing service name.

Check likely causes by HTTP status:

| HTTP status | Meaning | Check |
| --- | --- | --- |
| 401/403 | signing or policy failure | runtime role, SigV4 service name, AOSS access policy |
| 404 | wrong endpoint/index/path | endpoint normalization, `INDEX_NAME` |
| 400 | query or mapping problem | `VECTOR_FIELD_NAME`, vector dimension, query shape |
| 5xx | service-side failure | AOSS/OpenSearch service health and retry |

### Common fixes

- align vector field name with index mapping;
- align embedding vector dimension with index mapping;
- grant the backend role search permissions;
- check AOSS collection access policy;
- confirm the endpoint does not include an extra index path.

## 8. S3 result write failures

### Symptoms

- Bedrock or stub provider succeeds internally, but the job becomes `FAILED`;
- `failureReason` mentions S3 write, `PutObject`, access denied, bucket, or prefix;
- `resultObjectKey` is null.

### Checks

Verify runtime config:

```text
S3_WRITER_ENABLED=true
ANALYSIS_RESULT_BUCKET_NAME=<bucket-name>
ANALYSIS_RESULT_KEY_PREFIX=analysis-results
```

If `ANALYSIS_RESULT_BUCKET_NAME` is empty, the backend falls back to the source bucket.

Check write permission manually with a harmless test object in the expected prefix.

```bash
aws s3api put-object \
  --bucket <result-bucket> \
  --key analysis-results/_healthcheck/test.txt \
  --body /tmp/test.txt \
  --content-type text/plain
```

Expected:

- backend runtime role has `s3:PutObject`;
- bucket policy allows the configured prefix;
- generated Terraform content is non-empty.

### Common fixes

- set a dedicated result bucket;
- grant `s3:PutObject` on `analysis-results/*`;
- avoid writing results back into an upload-only prefix;
- check KMS policy if the bucket uses SSE-KMS.

## 9. SQS progress publish failures

### Symptoms

- job fails at progress publication;
- frontend cannot see job progress;
- application logs mention `SendMessage`, queue URL, or SQS access.

### Checks

Verify runtime config:

```text
ANALYSIS_SQS_PUBLISHER_ENABLED=true
AI_LOG_QUEUE_URL=<progress-queue-url>
TERRAFORM_LOG_QUEUE_URL=<result-queue-url>
```

If progress publishing is not required for a smoke test, keep `ANALYSIS_SQS_PUBLISHER_ENABLED=false` and rely on API state.

Expected:

- queue URLs match the deployed environment;
- backend runtime role has `sqs:SendMessage`;
- frontend/backend polling logic uses the same job/project correlation.

### Common fixes

- correct queue URL injection;
- grant `sqs:SendMessage`;
- confirm the queue belongs to the same account/region as the runtime identity;
- keep job state in RDB as the source of truth even when SQS progress is delayed.

## 10. Smoke validation commands

Local stub-path smoke:

```bash
BASE_URL=http://localhost:8080 \
PROJECT_ID=project-smoke \
SOURCE_BUCKET=example-bucket \
SOURCE_KEY=uploads/architecture-diagram.png \
bash scripts/smoke/create-analysis-job.sh
```

Expected:

```text
analysis job smoke assertions passed
status=SUCCEEDED
provider=stub-integrated-java
resultObjectKey=analysis-results/...
```

Production adapter smoke should use a real uploaded image object and adapter switches enabled.

```bash
BASE_URL=https://<backend-domain> \
PROJECT_ID=<project-id> \
SOURCE_BUCKET=<upload-bucket> \
SOURCE_KEY=<real-upload-object-key> \
bash scripts/smoke/create-analysis-job.sh
```

## 11. Interview explanation

```text
분석 job 실패를 단순히 AI 모델 문제로 보지 않고, S3 source read, reference retrieval, Bedrock generation, result object write, SQS progress publish로 adapter boundary를 나누어 진단할 수 있게 정리했습니다. RDB의 analysis_jobs 상태와 failureReason을 먼저 보고, 각 adapter의 runtime config와 IAM 권한, object key, index mapping을 순서대로 확인하는 runbook을 만들었습니다.
```
