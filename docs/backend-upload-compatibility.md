# Backend Upload Compatibility Contract

## 1. Purpose

The original Terraformers frontend uploaded architecture images through:

```text
POST /api/upload
```

The modernization backend provides a compatibility endpoint for this route so the source-derived frontend can keep the original upload entry point while still using the validated analysis-job pipeline internally.

## 2. Endpoint

```text
POST /api/upload
Content-Type: multipart/form-data
```

Required form field:

```text
file=<PNG/JPEG architecture image>
```

Optional form field:

```text
projectId=<explicit project identifier>
```

If `projectId` is omitted, the backend derives a normalized project id from the original filename.

## 3. Current behavior

The endpoint accepts the multipart file and records upload metadata:

```text
originalFilename
contentType
size
```

It now delegates source object handling to the upload storage boundary:

```text
UploadObjectStorageService
```

That boundary returns:

```text
storageProvider
binaryPersisted
sourceBucket
sourceKey
storageETag
```

Then the controller creates an analysis job through the existing analysis-job contract:

```text
projectId
sourceBucket
sourceKey
correlationId
```

The response includes the created analysis job status and result preview fields.

## 4. Response shape

```json
{
  "uploadMode": "analysis-job-compatibility",
  "storageProvider": "metadata-only",
  "binaryPersisted": false,
  "storageETag": null,
  "analysisJobId": "...",
  "projectId": "...",
  "sourceBucket": "example-bucket",
  "sourceKey": "browser-uploads/.../filename.png",
  "originalFilename": "AWS아키텍처.png",
  "contentType": "image/png",
  "size": 16,
  "status": "SUCCEEDED",
  "analysisMode": "INTEGRATED_JAVA",
  "provider": "stub-integrated-java",
  "resultObjectKey": "analysis-results/.../main.tf",
  "resultPreview": "...",
  "failureReason": null,
  "createdAt": "...",
  "updatedAt": "..."
}
```

## 5. Explicit boundary

There are now two explicit storage modes.

### Local/test metadata-only mode

```text
browser multipart upload
  -> upload metadata captured
  -> source reference generated
  -> binaryPersisted=false
  -> analysis job created
  -> Terraform draft preview returned
```

### S3 writer mode

```text
browser multipart upload
  -> binary object stored through S3 writer
  -> binaryPersisted=true
  -> persisted object reference used by analysis job
  -> project metadata records source persistence status
```

Reference:

```text
docs/backend-upload-binary-persistence.md
```

## 6. Validation

The endpoint is covered by:

```text
backend/src/test/java/com/terraformers/modernization/analysis/AnalysisUploadControllerTest.java
backend/src/test/java/com/terraformers/modernization/storage/UploadObjectStorageServiceTest.java
```

Assertions include:

- multipart upload returns `201 Created`;
- response includes an analysis job id;
- filename, content type, and size are preserved;
- source reference is generated under `browser-uploads/...`;
- default local/test mode reports `storageProvider=metadata-only` and `binaryPersisted=false`;
- S3 writer unit coverage verifies `PutObject` request fields and returned `eTag`;
- local/stub profile returns `SUCCEEDED` with Terraform draft preview;
- empty file returns `400 Bad Request` instead of `500`.

## 7. Portfolio explanation

```text
원본 Terraformers 프론트의 `/api/upload` 진입점을 유지하면서, 현재 백엔드의 analysis job 파이프라인으로 연결되는 호환 endpoint를 추가했습니다. 이후 업로드 파일 처리를 별도 저장소 경계로 분리해, 로컬·테스트에서는 기존처럼 metadata-only source reference를 사용하고 운영 검증에서는 S3 writer를 켰을 때 실제 PutObject 결과를 프로젝트 메타데이터에 남기도록 확장했습니다. 따라서 업로드 흐름을 과장하지 않고, 실제 바이너리 저장 여부를 `binaryPersisted`와 `sourceBinaryPersisted`로 확인할 수 있습니다.
```
