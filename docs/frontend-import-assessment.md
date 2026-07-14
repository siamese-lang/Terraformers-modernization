# Frontend Import and Backend Contract Assessment

## 1. Decision

The frontend source should be imported selectively from the previous private repository, not by importing the full repository history and not by requiring the user to keep both repositories locally.

Source repository inspected through the GitHub connector:

```text
siamese-lang/rdb-refactor
app/Terraformers-main/frontend
```

Target repository:

```text
siamese-lang/Terraformers-modernization
```

The imported frontend should support the Terraformers team-project service flow, but it must remain secondary to the backend/cloud modernization portfolio.

## 2. Source frontend shape

The previous frontend is a Create React App project using React 18, React Router, Amplify, Axios, Cloudscape, Monaco Editor, and upload/tree/editor UI dependencies.

Key runtime characteristics:

- `react-scripts` build/start workflow;
- Cognito/Amplify authentication dependency;
- Axios wrapper with `REACT_APP_API_BASE_URL` and Bearer token injection;
- chat-style upload UI;
- project tree / editor UI;
- public project and comment UI;
- AWS credential settings UI that should not be carried forward as-is.

## 3. Current backend gap

The current modernization backend has a validated local/stub endpoint set centered on:

```text
POST /api/analysis/jobs
GET  /api/analysis/jobs/{id}
```

The previous frontend expects a broader product API surface. Importing it without a contract bridge would create a visually large but broken UI.

## 4. Initial frontend baseline

The first frontend commit intentionally introduces a smaller browser smoke baseline instead of the full legacy UI.

Current baseline:

```text
frontend/package.json
frontend/public/index.html
frontend/src/index.js
frontend/src/App.js
frontend/src/api.js
frontend/src/styles.css
frontend/.env.example
```

This baseline:

- keeps the browser flow focused on the validated analysis job API;
- uses CRA `proxy` to send local `/api/*` requests to `http://localhost:8080` without broad CORS changes;
- displays job status, provider, result object key, Terraform preview, and raw JSON response;
- clearly marks dashboard, project tree, comments, Terraform draft editing, and settings as backend contract work items rather than deleting them from the product direction.

This is not the final frontend import. It is the first stable browser-facing validation layer.

## 5. API contract classification

| Frontend expectation | Source usage | Decision | Rationale |
| --- | --- | --- | --- |
| `POST /api/upload` | image upload flow | Implement compatibility backend endpoint or adapt frontend to call analysis job creation after upload metadata is available | Core product flow. Do not remove. |
| `GET /api/bedrock/logs?queueUrl=...&projectId=...` | old SQS polling flow | Replace with analysis job status polling or introduce a safer compatibility endpoint | Queue URL polling is legacy-specific. Current backend has analysis job lifecycle and can expose status/result without requiring queue URL in the browser. |
| `GET /api/project-tree` | my project tree | Implement minimal project/file tree after project metadata is introduced | Useful service feature and valid demo flow. |
| `GET /api/project-tree/{projectId}` | public project preview tree | Implement after project metadata is introduced | Supports public project exploration. |
| `GET /api/public-projects` | dashboard public list | Implement after project visibility is modeled | Valid feature; do not remove solely because it is currently missing. |
| `POST /api/updateProjectVisible` | public/private toggle | Implement after project entity and visibility field exist | Valid service behavior. |
| `GET /api/getProjectInfrastructureImage/{projectId}` | project preview image | Implement as metadata/result lookup or adapt to object reference | Valid if upload metadata is persisted. |
| `GET /api/terraform-code/{fileId}` | editor read | Implement after generated result/file metadata exists | Valid editor flow. |
| `POST /api/update-terraform-code/{fileId}` | editor save | Implement only after persistence model is clear | Valid if treated as stored draft update, not actual Terraform execution. |
| `GET /api/terraform/tfstate/{projectId}` | tfstate node display | Defer | Not part of current generation baseline. Requires real Terraform execution/state integration. |
| `POST /api/terraform/run/{projectId}` / destroy/logs | Terraform execution flow | Defer | Out of current local/stub baseline. Should not be faked. |
| `GET /api/getProjectComments/{projectId}` | public comments | Implement after project/comment model exists | Valid public project feature. |
| `POST /api/addProjectComment` | comment create | Implement after project/comment model exists | Valid public project feature. |
| `POST /api/update-aws-credentials` / `GET /api/aws-credentials` | settings page | Do not import as-is | User-entered AWS access keys conflict with the current runtime secret management direction. Replace with runtime configuration status or remove from demo flow. |
| text-only chat | unsupported message | Keep unsupported | Previous contract already treats text chat as unsupported. No `/api/chat` backend should be added for this portfolio. |

## 6. Import candidates

Import only public-safe frontend application files needed for build and browser smoke.

Candidate include paths for later staged import:

```text
app/Terraformers-main/frontend/package.json
app/Terraformers-main/frontend/package-lock.json, if present
app/Terraformers-main/frontend/public/*
app/Terraformers-main/frontend/src/App.js
app/Terraformers-main/frontend/src/index.js
app/Terraformers-main/frontend/src/index.css
app/Terraformers-main/frontend/src/components/*
app/Terraformers-main/frontend/src/api/*
app/Terraformers-main/frontend/src/utils/*
app/Terraformers-main/frontend/src/assets/*
```

Candidate exclude paths:

```text
node_modules/
build/
.env*
aws-exports.js
aws-exports*.js
Dockerfile.backup
frontend deployment workflows
old private repository history
any generated credentials, tokens, account IDs, or environment-specific config
```

`aws-exports.test.js` may be inspected as a test placeholder, but it should not be imported unless it is confirmed to contain only fake values and is still needed by tests.

## 7. Backend implementation priority

Do not remove UI controls simply because the current backend lacks an endpoint. Classify each control by product value first.

Recommended backend order before full browser smoke:

1. Project metadata model
   - project id;
   - project name;
   - visibility;
   - source object reference;
   - result object key;
   - created/updated timestamps.
2. Upload compatibility endpoint
   - accept image upload request;
   - create project/file metadata;
   - call or create analysis job;
   - return response shape the frontend can render.
3. Analysis job status bridge
   - allow frontend polling by job id;
   - avoid exposing queue URL as the browser polling contract.
4. Project tree read endpoint
   - return root project node;
   - include source image node and generated Terraform result node.
5. Terraform draft read/update endpoint
   - read generated draft;
   - allow update only as draft content, not Terraform execution.
6. Public project list and visibility update.
7. Comments for public projects.

Deferred:

- Terraform run/destroy/tfstate;
- real Bedrock/OpenSearch/SQS adapter browser behavior;
- user-provided AWS credential storage.

## 8. Frontend stabilization priority

1. Verify the initial browser smoke baseline builds.
2. Start backend locally and run the frontend against `/api/analysis/jobs`.
3. Replace old `/api/bedrock/logs` queue polling with analysis job status polling or a safe compatibility endpoint.
4. Add project metadata/tree API before restoring the full dashboard/users UI.
5. Keep dashboard/users/chat/settings icons only when each has either a working backend path or a clear disabled/coming-soon state.
6. Replace AWS credentials settings with runtime configuration status or remove settings from the smoke path.
7. Run browser smoke.

## 9. Minimum browser smoke target

```text
Open frontend
  -> use local demo analysis form
  -> create analysis job
  -> show SUCCEEDED status
  -> show Terraform draft preview
  -> show result object key
  -> later: open generated Terraform draft in editor
```

## 10. Boundary for portfolio explanation

```text
프론트엔드는 새로 만든 별도 제품이 아니라 기존 팀 프로젝트 Terraformers의 사용 흐름을 보존하기 위해 선별 이관했습니다. 동작하지 않는 버튼을 무조건 제거하지 않고, 프로젝트 핵심 흐름에 해당하는 업로드, 분석 작업, 결과 조회, 프로젝트 트리, 코드 조회/수정은 백엔드 계약으로 승격했습니다. 반면 브라우저에서 AWS Access Key를 입력받는 설정처럼 운영 보안 방향과 맞지 않는 기능은 이관하지 않고, runtime secret/config 검증 방향으로 대체했습니다. 첫 단계에서는 전체 레거시 UI를 한 번에 옮기지 않고, 이미 검증된 분석 작업 API를 브라우저에서 호출하는 최소 smoke 화면부터 추가했습니다.
```
