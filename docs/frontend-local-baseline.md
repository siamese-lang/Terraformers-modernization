# Frontend Local Baseline

## 1. Purpose

This frontend baseline is the first public-safe browser smoke layer for the Terraformers modernization project.

It is not the full legacy frontend import yet. It preserves the core product direction from the previous Terraformers UI while avoiding a large, broken UI surface before the backend contract exists.

## 2. Source influence

The previous private frontend used:

```text
siamese-lang/rdb-refactor
app/Terraformers-main/frontend
```

The original UI included:

- chat-style upload interaction;
- Cognito/Amplify authentication;
- project tree and editor flows;
- public projects and comments;
- settings that accepted AWS credentials in the browser.

This baseline keeps the browser smoke centered on the validated modernization backend contract:

```text
POST /api/analysis/jobs
GET  /api/analysis/jobs/{id}
```

## 3. Runtime behavior

The app lets a user enter:

- `projectId`;
- `sourceBucket`;
- `sourceKey`.

It then creates an analysis job and displays:

- job status;
- provider;
- result object key;
- Terraform draft preview;
- raw response for debugging.

## 4. Local development

Start the backend first:

```bash
cd backend
mvn spring-boot:run
```

Start the frontend in another terminal:

```bash
cd frontend
npm install
npm start
```

During local CRA development, `frontend/package.json` uses:

```json
"proxy": "http://localhost:8080"
```

This allows browser requests to `/api/*` to reach the backend without opening broad CORS rules.

## 5. Verification

Run from the repository root:

```bash
bash scripts/checks/frontend-local-verification.sh
```

Expected result:

```text
[frontend] local verification completed
```

## 6. Deliberate limitations

The following legacy UI contracts are not removed from the project direction, but they are not implemented in this first browser baseline:

- upload compatibility endpoint;
- project metadata model;
- project tree;
- Terraform draft read/update;
- public project list;
- visibility toggle;
- comments;
- Cognito browser auth;
- runtime configuration status.

The following remain deferred until real integration exists:

- Terraform run/destroy;
- tfstate display;
- real S3/SQS/Bedrock/OpenSearch browser behavior;
- user-entered AWS credential storage.

## 7. Portfolio explanation

```text
프론트엔드는 이전 팀 프로젝트의 사용 흐름을 보존하기 위해 선별 이관하되, 아직 백엔드 계약이 없는 기능을 겉모습만 살려 두지 않았습니다. 먼저 검증된 분석 작업 생성/조회 API를 브라우저에서 호출하는 최소 smoke 화면을 추가했고, 프로젝트 트리·공개 프로젝트·댓글·코드 편집은 후속 백엔드 계약으로 분리했습니다. 이를 통해 프론트 화면을 보여주기 위한 임시 구현이 아니라, 백엔드/API 검증 가능한 단위부터 단계적으로 연결하는 방식으로 정리했습니다.
```
