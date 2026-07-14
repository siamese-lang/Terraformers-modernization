# Frontend Upload Analysis Import Pass

## 1. Scope

This pass imports the original Terraformers frontend's core product direction:

```text
chat-style architecture image selection
  -> upload request
  -> analysis logs/status
  -> Terraform draft preview
```

It is source-derived from the original frontend, especially:

```text
src/components/AiChat.js
src/components/Dropzone.js
src/components/Modal.js
```

The implementation is intentionally adapted to the modernization backend's current validated contract.

## 2. Original behavior observed

The previous `Dropzone` accepted PNG/JPEG files, posted multipart data to:

```text
POST /api/upload
```

Then, when the response contained a queue URL, it polled:

```text
GET /api/bedrock/logs?queueUrl=...&projectId=...
```

The previous `AiChat` listened for Bedrock events and rendered Terraform code in the chat result area.

## 3. Modernized behavior in this pass

The browser now keeps the original upload entry point:

```text
POST /api/upload
```

The backend compatibility endpoint creates an analysis job internally and returns the analysis job result fields to the browser.

When a user selects a PNG/JPEG image, the frontend:

1. shows the image in the chat thread;
2. sends the file as multipart form data to `/api/upload`;
3. receives the created analysis job id and source reference;
4. polls `GET /api/analysis/jobs/{id}` only if the upload response is not already terminal;
5. renders `resultPreview` as Terraform draft output.

## 4. Current compatibility boundary

This pass does not yet claim production binary object persistence.

Current stage:

```text
browser multipart upload
  -> backend captures upload metadata
  -> backend generates source reference
  -> backend creates analysis job
  -> browser renders Terraform draft preview
```

Future production stage:

```text
browser multipart upload
  -> backend stores binary object through S3 writer
  -> persisted object reference is used by analysis provider
  -> project metadata and file tree are updated
```

This boundary is documented in:

```text
docs/backend-upload-compatibility.md
```

## 5. Explicit exclusions

The following original behaviors remain excluded or deferred:

- browser-visible SQS queue URL polling;
- Terraform run/destroy/tfstate controls;
- AWS credential settings in the browser;
- Monaco editor integration;
- project tree/editor controls;
- public projects/comments.

These should be reintroduced only when their backend contracts are implemented or clearly disabled.

## 6. Verification

Run from the repository root:

```bash
bash scripts/checks/frontend-import-verification.sh
```

Backend contract coverage:

```text
backend/src/test/java/com/terraformers/modernization/analysis/AnalysisUploadControllerTest.java
```

For browser smoke, start the backend first:

```bash
cd backend
mvn spring-boot:run
```

Then start the frontend:

```bash
cd frontend
npm start
```

Expected browser path:

```text
http://localhost:3000
```

Expected smoke result:

```text
Select PNG/JPEG image
  -> POST /api/upload
  -> create analysis job
  -> show analysis logs
  -> show SUCCEEDED result
  -> show Terraform draft preview
```

If the browser still returns HTTP 500 after this pass, inspect the backend terminal stack trace. The frontend prints backend response details when available, but server-side exceptions must be diagnosed from the Spring Boot log.

## 7. Portfolio explanation

```text
기존 Terraformers의 채팅형 이미지 업로드 흐름을 그대로 새로 만들지 않고, 원본 프론트의 AiChat/Dropzone/Modal 구조를 기준으로 선별 이관했습니다. 원본과 동일한 `/api/upload` 진입점을 유지하되, 내부적으로는 현재 검증된 analysis job 파이프라인에 연결했습니다. 다만 실제 S3 바이너리 저장까지 완료했다고 과장하지 않고, 현재 단계는 업로드 메타데이터와 source reference를 통해 Terraform 초안 미리보기를 확인하는 호환 계약으로 분리했습니다.
```
