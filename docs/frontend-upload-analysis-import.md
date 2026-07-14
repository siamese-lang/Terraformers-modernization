# Frontend Upload Analysis Import Pass

## 1. Scope

This pass imports the original Terraformers frontend's core product direction:

```text
chat-style architecture image selection
  -> analysis request
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

The browser flow now uses the backend contract already validated by local smoke tests:

```text
POST /api/analysis/jobs
GET  /api/analysis/jobs/{id}
```

When a user selects a PNG/JPEG image, the frontend:

1. shows the image in the chat thread;
2. builds a public-safe source reference from `.env` defaults;
3. creates an analysis job;
4. polls the job if it is not already terminal;
5. renders `resultPreview` as Terraform draft output.

## 4. Why `/api/upload` is not implemented here

This pass does not claim binary upload is complete.

The current backend contract accepts:

```text
projectId
sourceBucket
sourceKey
correlationId
```

Therefore this frontend pass bridges the browser-selected image into an analysis job source reference instead of pretending that object storage upload is complete.

A real upload compatibility endpoint remains future backend work.

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
  -> create analysis job
  -> show analysis logs
  -> show SUCCEEDED result
  -> show Terraform draft preview
```

## 7. Portfolio explanation

```text
기존 Terraformers의 채팅형 이미지 업로드 흐름을 그대로 새로 만들지 않고, 원본 프론트의 AiChat/Dropzone/Modal 구조를 기준으로 선별 이관했습니다. 다만 원본의 SQS queue URL 브라우저 polling과 Terraform 실행/삭제, 브라우저 AWS credential 입력은 현재 운영 보안 방향과 맞지 않거나 백엔드 계약이 없으므로 제외했습니다. 대신 이미 검증된 analysis job API에 연결하여, 이미지 선택부터 Terraform 초안 미리보기까지 브라우저에서 확인 가능한 흐름으로 안정화했습니다.
```
