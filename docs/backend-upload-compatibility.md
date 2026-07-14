# Backend Upload Compatibility Contract

## 1. Purpose

The original Terraformers frontend uploaded architecture images through:

```text
POST /api/upload
```

The modernization backend now provides a compatibility endpoint for this route so the source-derived frontend can keep the original upload entry point while still using the validated analysis-job pipeline internally.

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

Then it creates an analysis job through the existing analysis-job contract:

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

This endpoint does not yet claim production binary object persistence.

Current stage:

```text
browser multipart upload
  -> upload metadata captured
  -> source reference generated
  -> analysis job created
  -> Terraform draft preview returned
```

Future production stage:

```text
browser multipart upload
  -> binary object stored through S3 writer
  -> persisted object reference used by analysis provider
  -> project metadata and file tree updated
```

## 6. Validation

The endpoint is covered by:

```text
backend/src/test/java/com/terraformers/modernization/analysis/AnalysisUploadControllerTest.java
```

Assertions include:

- multipart upload returns `201 Created`;
- response includes an analysis job id;
- filename, content type, and size are preserved;
- source reference is generated under `browser-uploads/...`;
- local/stub profile returns `SUCCEEDED` with Terraform draft preview;
- empty file returns `400 Bad Request` instead of `500`.

## 7. Portfolio explanation

```text
원본 Terraformers 프론트의 `/api/upload` 진입점을 유지하면서, 현재 백엔드의 analysis job 파이프라인으로 연결되는 호환 endpoint를 추가했습니다. 이 단계에서는 파일 메타데이터와 source reference를 바탕으로 분석 작업을 생성하며, 실제 S3 바이너리 저장은 후속 production adapter 작업으로 분리했습니다. 따라서 원본 서비스 흐름을 복원하되, 아직 구현되지 않은 저장소 기능을 완료된 것처럼 표현하지 않습니다.
```
