# Runbook

## 1. Purpose

This document is the top-level runbook for the Terraformers backend and cloud infrastructure modernization project.

The current modernization direction is backend-owned analysis orchestration. The core runtime is the Spring Boot backend. Python analysis service behavior is treated as legacy reference, not as the default production path.

Runbooks are intended to help verify runtime behavior, isolate failures by adapter boundary, and collect sanitized evidence for the portfolio.

## 2. Current backend-owned analysis flow

```text
POST /api/analysis/jobs
  -> analysis_jobs row is created
  -> ObjectReader checks the uploaded source object
  -> ReferenceRetriever retrieves reference patterns
  -> AnalysisProvider generates Terraform HCL
  -> AnalysisResultStorage writes Terraform HCL through ObjectWriter
  -> analysis_jobs.result_object_key is recorded
  -> ProgressPublisher emits progress/result state
  -> GET /api/analysis/jobs/{id} verifies state
```

The detailed failure runbook is maintained here:

- [`docs/runbooks/backend-analysis-adapter-failures.md`](runbooks/backend-analysis-adapter-failures.md)

## 3. Default local/CI-safe path

The default path must run without AWS credentials.

```text
S3_READER_ENABLED=false
S3_WRITER_ENABLED=false
BEDROCK_PROVIDER_ENABLED=false
BEDROCK_EMBEDDING_ENABLED=false
OPENSEARCH_RETRIEVER_ENABLED=false
ANALYSIS_SQS_PUBLISHER_ENABLED=false
```

Expected behavior:

- `StubObjectReader` is used;
- `StubObjectWriter` is used;
- `StubReferenceRetriever` is used;
- `StubAnalysisProvider` is used;
- `LoggingProgressPublisher` is used;
- smoke test returns `SUCCEEDED`, `resultObjectKey`, and `resultPreview`.

## 4. Local smoke validation

Run after the backend starts.

```bash
BASE_URL=http://localhost:8080 \
PROJECT_ID=project-smoke \
SOURCE_BUCKET=example-bucket \
SOURCE_KEY=uploads/architecture-diagram.png \
bash scripts/smoke/create-analysis-job.sh
```

Expected output:

```text
analysis job smoke assertions passed
status=SUCCEEDED
provider=stub-integrated-java
resultObjectKey=analysis-results/...
```

## 5. Production adapter enablement order

Enable only one new runtime dependency at a time.

```text
1. S3_READER_ENABLED=true
2. S3_WRITER_ENABLED=true
3. BEDROCK_PROVIDER_ENABLED=true
4. BEDROCK_EMBEDDING_ENABLED=true
5. OPENSEARCH_RETRIEVER_ENABLED=true
6. ANALYSIS_SQS_PUBLISHER_ENABLED=true
```

This order isolates failures. For example, if source object read fails, fix S3 reader before introducing Bedrock or OpenSearch into the same test.

## 6. Common runtime checks

For Kubernetes deployment validation:

```bash
kubectl get deploy,po,svc,endpoints -n default
kubectl get events -n default --sort-by=.lastTimestamp | tail -80
kubectl rollout status deployment/terraformers-backend -n default
kubectl logs deployment/terraformers-backend -n default --tail=200
```

Use the actual deployment name if the manifest names the backend differently.

Check in this order:

1. Pod status and rollout status.
2. Service endpoints.
3. Runtime config key presence, not secret values.
4. API smoke result.
5. `analysis_jobs` API state.
6. Adapter-specific logs and permissions.

## 7. Adapter failure boundaries

| Boundary | Runtime switch | Typical failure |
| --- | --- | --- |
| `ObjectReader` | `S3_READER_ENABLED` | source object missing, `s3:GetObject` denied, wrong content type |
| `ObjectWriter` | `S3_WRITER_ENABLED` | result bucket missing, `s3:PutObject` denied, blocked prefix |
| `AnalysisProvider` | `BEDROCK_PROVIDER_ENABLED` | Bedrock model id missing, timeout, unsupported image payload |
| `EmbeddingProvider` | `BEDROCK_EMBEDDING_ENABLED` | embedding model id missing, response format mismatch |
| `ReferenceRetriever` | `OPENSEARCH_RETRIEVER_ENABLED` | wrong endpoint, wrong index, vector field mismatch, SigV4/IAM failure |
| `ProgressPublisher` | `ANALYSIS_SQS_PUBLISHER_ENABLED` | queue URL mismatch, `sqs:SendMessage` denied |

For detailed triage steps, use [`backend-analysis-adapter-failures.md`](runbooks/backend-analysis-adapter-failures.md).

## 8. Evidence to collect

For each validation run, collect:

- adapter switches used during the run;
- request payload with tokens and secrets removed;
- POST `/api/analysis/jobs` response;
- GET `/api/analysis/jobs/{id}` response;
- backend logs around the job id;
- generated `resultObjectKey`;
- relevant sanitized S3/OpenSearch/SQS configuration summaries.

Do not commit:

- access keys or tokens;
- account IDs;
- secret values;
- kubeconfig;
- tfstate or tfvars;
- raw production logs containing private identifiers;
- private object contents.

## 9. Portfolio explanation

```text
운영환경 고도화 과정에서 분석 기능을 Python side service에 의존하는 구조로 두지 않고, Spring Boot backend가 analysis job lifecycle을 소유하도록 정리했습니다. S3 읽기, reference retrieval, Bedrock 호출, 결과 object 저장, SQS 발행을 adapter boundary로 나누었기 때문에 장애가 발생했을 때 analysis_jobs 상태와 failureReason을 기준으로 어느 외부 의존성에서 실패했는지 분리해 확인할 수 있습니다.
```
