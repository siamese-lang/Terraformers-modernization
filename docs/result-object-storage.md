# Result Object Storage

## 1. Purpose

Generated Terraform HCL should not live only inside API response previews or relational metadata.

The backend stores generated Terraform content through an object storage boundary and records the object key in `analysis_jobs.result_object_key`.

This keeps the database focused on job state and metadata while object storage owns generated file content.

## 2. Flow

```text
AnalysisProvider
  -> returns generated Terraform HCL
AnalysisResultStorage
  -> builds result object key
ObjectWriter
  -> stores text content
AnalysisJobEntity
  -> stores result_object_key and result_preview
```

## 3. Local/CI behavior

Local and CI verification use `StubObjectWriter`.

```text
S3_WRITER_ENABLED=false
```

The stub writer does not call AWS. It returns the requested bucket/key so tests can verify object key generation and analysis job state transitions without credentials.

## 4. Production behavior

Production can enable S3 result storage.

```text
S3_WRITER_ENABLED=true
ANALYSIS_RESULT_BUCKET_NAME=<bucket-name>
ANALYSIS_RESULT_KEY_PREFIX=analysis-results
```

If `ANALYSIS_RESULT_BUCKET_NAME` is not set, the backend falls back to the source bucket used by the analysis job.

Default key pattern:

```text
analysis-results/{projectId}/{yyyy}/{MM}/{dd}/{analysisJobId}/main.tf
```

## 5. Smoke validation

The smoke script creates an analysis job, fetches it again, and validates the persisted job state.

```bash
BASE_URL=http://localhost:8080 \
PROJECT_ID=project-smoke \
SOURCE_BUCKET=example-bucket \
SOURCE_KEY=uploads/architecture-diagram.png \
bash scripts/smoke/create-analysis-job.sh
```

Default assertions:

```text
POST /api/analysis/jobs returns HTTP 201
GET /api/analysis/jobs/{id} returns HTTP 200
status = SUCCEEDED
resultObjectKey is not empty
resultPreview is not empty
```

For a deliberate failure-path check, override expectations:

```bash
EXPECT_STATUS=FAILED \
EXPECT_RESULT_KEY=false \
EXPECT_RESULT_PREVIEW=false \
bash scripts/smoke/create-analysis-job.sh
```

## 6. Operational checks

When a job succeeds, verify:

```text
analysis_jobs.status = SUCCEEDED
analysis_jobs.result_object_key is not null
analysis_jobs.result_preview is not null
S3 object exists at s3://{resultBucket}/{resultObjectKey}
```

If the job fails after Bedrock succeeds, check the object writer path separately:

- bucket exists;
- IAM role has `s3:PutObject` permission;
- object key prefix is allowed by bucket policy;
- generated content is not empty;
- application logs show S3 writer failure rather than Bedrock or OpenSearch failure.

## 7. Portfolio explanation

```text
분석 결과를 DB에 큰 문자열로만 저장하지 않고, 생성된 Terraform 파일은 object storage에 저장하고 RDB에는 job 상태와 object key를 기록하도록 분리했습니다. 이를 통해 S3 object 저장 실패와 DB job 상태 갱신 실패를 구분해 점검할 수 있고, backend가 분석 job lifecycle과 산출물 위치를 함께 관리하는 구조를 만들었습니다.
```
