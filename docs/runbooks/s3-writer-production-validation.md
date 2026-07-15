# S3 Writer Production Validation Runbook

## 1. Purpose

This runbook validates only the upload-object writer boundary:

```text
POST /api/upload
  -> UploadObjectStorageService
  -> S3 PutObject
  -> analysis job receives the persisted sourceBucket/sourceKey
  -> S3 head-object confirms the object exists
```

It must not be used as proof that S3 reader, Bedrock, OpenSearch, SQS publisher, public image serving, or browser cloud credential settings are complete.

## 2. Workflow

Use the manual GitHub Actions workflow:

```text
S3 Writer Production Validation
```

The workflow runs:

```text
scripts/checks/s3-writer-production-validation.sh
```

The backend starts with H2/local runtime defaults, but the S3 writer flag is enabled:

```text
TERRAFORMERS_STORAGE_S3_WRITER_ENABLED=true
TERRAFORMERS_STORAGE_S3_READER_ENABLED=false
TERRAFORMERS_ANALYSIS_BEDROCK_PROVIDER_ENABLED=false
TERRAFORMERS_ANALYSIS_BEDROCK_EMBEDDING_ENABLED=false
TERRAFORMERS_ANALYSIS_OPENSEARCH_RETRIEVER_ENABLED=false
TERRAFORMERS_ANALYSIS_SQS_PUBLISHER_ENABLED=false
```

## 3. Required AWS permission

The GitHub runner identity needs the minimum S3 permissions for the selected validation bucket and prefix:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::<bucket>/<prefix>/*"
    }
  ]
}
```

`DeleteObject` is required only when `cleanup_object=true`.

## 4. Credential options

Preferred option:

```text
aws_role_to_assume=<GitHub OIDC IAM role ARN>
```

Fallback option:

```text
Repository secret AWS_ACCESS_KEY_ID
Repository secret AWS_SECRET_ACCESS_KEY
Optional repository secret AWS_SESSION_TOKEN
```

Do not store AWS credentials in the frontend or repository files.

## 5. Inputs

```text
aws_region      AWS region of the bucket, for example ap-northeast-2
upload_bucket   existing S3 bucket name
upload_prefix   temporary validation prefix
cleanup_object  true by default
```

Recommended prefix:

```text
terraformers-modernization-validation
```

## 6. Success criteria

The workflow must prove all of the following:

```text
1. /api/upload returns 201 Created.
2. response.storageProvider == "s3".
3. response.binaryPersisted == true.
4. response.sourceBucket == selected upload bucket.
5. response.sourceKey is under the selected prefix.
6. response.sourceETag is non-empty.
7. aws s3api head-object succeeds for sourceBucket/sourceKey.
8. head-object ContentType is image/png.
```

The workflow uploads the evidence artifact:

```text
s3-writer-production-validation
```

Expected artifact files:

```text
backend.log
upload-response.json
s3-head-object.json
s3-writer-production-validation.md
validation-architecture.png
```

## 7. Failure interpretation

Common failures and likely causes:

| Failure | Likely cause |
|---|---|
| `sts get-caller-identity` fails | missing/incorrect GitHub AWS credentials or role trust policy |
| backend does not become healthy | application config/runtime error; inspect `backend.log` |
| `/api/upload` returns 502 | S3 PutObject failed; inspect backend log and IAM permissions |
| `storageProvider` is not `s3` | S3 writer flag did not bind correctly |
| `head-object` fails | object was not written, wrong bucket/key, or missing GetObject/HeadObject permission |

## 8. Portfolio explanation

```text
S3 writer 검증은 전체 AWS 연동을 한 번에 켠 것이 아니라, 업로드 이미지가 실제 S3 객체로 저장되는 경계만 분리해 검증한 작업입니다. `/api/upload` 요청 후 응답의 `storageProvider=s3`, `binaryPersisted=true`, `sourceETag`를 확인하고, 같은 bucket/key에 대해 `head-object`를 수행해 객체 존재를 검증했습니다. 이 단계에서는 S3 read, Bedrock, OpenSearch, SQS는 의도적으로 비활성화하여 장애 원인 범위를 S3 writer로 제한했습니다.
```
