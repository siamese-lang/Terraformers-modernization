# Backend Upload Binary Persistence

## 1. Purpose

The upload compatibility endpoint now has an explicit storage boundary before analysis-job creation.

This keeps the original Terraformers browser entry point:

```text
POST /api/upload
```

but separates two runtime modes:

```text
metadata-only local/test mode
S3 writer production adapter mode
```

## 2. Current storage boundary

New backend storage boundary:

```text
backend/src/main/java/com/terraformers/modernization/storage/UploadObjectStorageService.java
```

The controller no longer builds a source reference by itself. It asks the storage service to return:

```text
provider
binaryPersisted
bucket
key
eTag
```

Then the analysis job uses the returned `bucket/key` as the source object reference.

## 3. Local/test mode

Default behavior remains safe for local and GitHub Actions verification:

```yaml
terraformers:
  storage:
    s3-writer-enabled: false
```

In this mode:

```text
browser multipart upload
  -> source bucket/key generated
  -> binary object is not written
  -> analysis job uses metadata source reference
  -> project metadata records sourceBinaryPersisted=false
```

Response excerpt:

```json
{
  "storageProvider": "metadata-only",
  "binaryPersisted": false,
  "sourceBucket": "example-bucket",
  "sourceKey": "browser-uploads/.../image.png"
}
```

This preserves the earlier validated local/stub behavior and avoids requiring AWS credentials in routine verification.

## 4. S3 writer mode

Production adapter validation should enable only this boundary first:

```yaml
terraformers:
  storage:
    s3-writer-enabled: true
  upload:
    source-bucket: <real-source-bucket>
    source-prefix: browser-uploads
```

Expected behavior:

```text
browser multipart upload
  -> PutObject to S3
  -> returned bucket/key/eTag recorded
  -> analysis job receives persisted source reference
  -> project metadata records sourceBinaryPersisted=true
```

Response excerpt:

```json
{
  "storageProvider": "s3",
  "binaryPersisted": true,
  "storageETag": "...",
  "sourceBucket": "<real-source-bucket>",
  "sourceKey": "browser-uploads/.../image.png"
}
```

## 5. Error behavior

If S3 writer mode is enabled and object persistence fails, `/api/upload` returns a storage failure instead of silently continuing with a fake source object.

```text
S3 writer failure -> 502 Bad Gateway
```

This is intentional: when a production adapter is enabled, downstream analysis should not run against a source key that was not actually written.

## 6. Verification

Covered by:

```text
backend/src/test/java/com/terraformers/modernization/analysis/AnalysisUploadControllerTest.java
backend/src/test/java/com/terraformers/modernization/storage/UploadObjectStorageServiceTest.java
```

Assertions include:

```text
s3-writer-enabled=false
  -> metadata-only source reference
  -> no S3 PutObject call

s3-writer-enabled=true
  -> PutObject request uses configured bucket/key/content-type/content-length
  -> result provider=s3
  -> binaryPersisted=true
  -> eTag is returned
```

Run through GitHub Actions:

```text
Backend Local Verification
```

## 7. Portfolio explanation

```text
기존 Terraformers의 이미지 업로드 진입점은 유지하되, 업로드 파일을 분석 job에 넘기기 전에 저장소 경계를 분리했습니다. 로컬·테스트에서는 기존과 동일하게 metadata-only source reference를 사용하고, 운영 검증에서는 `S3_WRITER_ENABLED`를 켰을 때 실제 S3 PutObject 결과를 sourceBucket/sourceKey/eTag로 기록하도록 했습니다. 이로써 실제 바이너리 저장 여부를 응답과 프로젝트 메타데이터에서 확인할 수 있게 했으며, AWS credential을 브라우저에 입력하는 방식은 되살리지 않았습니다.
```
