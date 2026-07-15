# Frontend Public Projects Surface

## 1. Scope

This pass adds a small public project list and comment surface to the selected original frontend import path.

It preserves the modernization direction:

```text
/api/public-projects
  -> list PUBLIC projects
  -> show source metadata and source persistence status
  -> select a project
  -> GET /api/project-tree/{projectId}
  -> inspect source metadata and stored Terraform draft
  -> GET/POST project comments through compatibility endpoints
```

The component is intentionally smaller than the original `AiChat` dashboard surface.

## 2. Files

```text
frontend/src/components/PublicProjectsReadOnly.js
frontend/src/components/AiChat.js
frontend/src/styles/public-projects.css
frontend/src/utils/api.js
```

`/api/public-projects`, `/api/getProjectComments/`, and `/api/addProjectComment` are auth-optional in the current frontend compatibility path list.

## 3. Behavior

The public projects panel:

```text
mounts
  -> GET /api/public-projects
  -> renders projectName/name, source metadata, and source persistence status
  -> clicking a project updates selectedProjectId
  -> ProjectTreeReadOnly loads /api/project-tree/{projectId}
  -> comments panel loads /api/getProjectComments/{projectId}
```

The project tree remains the existing read-only tree. Clicking `main.tf` still reads:

```text
GET /api/projects/{projectId}/terraform/main.tf
```

The source persistence display is informational:

```text
sourceStorageProvider · persisted|metadata only
```

## 4. Explicit exclusions

The following original behaviors remain excluded:

```text
likes/dislikes
comment edit/delete
project edit/delete
Terraform run/destroy/tfstate polling
browser AWS credential settings
public binary image preview through S3 URL
```

A public project list item may show upload metadata such as `originalFilename`, `sourceBucket`, `sourceKey`, and `sourceBinaryPersisted`. This does not claim public object serving or browser download unless a source object read/download contract is added later.

## 5. Verification

Run through GitHub Actions:

```text
Frontend Import Verification
Backend Local Verification
```

Recommended browser smoke only when UI inspection is needed:

```text
upload image
PATCH visibility to PUBLIC through backend/API test path or a short API call
refresh public projects panel
select public project
confirm project tree and main.tf preview remain read-only
confirm comments can be listed/added for PUBLIC projects
confirm source persistence status is visible
```

## 6. Portfolio explanation

```text
원본 Terraformers의 공개 프로젝트 탐색 흐름을 전체 대시보드까지 무리하게 복원하지 않고, 현재 검증된 `/api/public-projects`, 프로젝트 트리, 공개 댓글 계약에 맞춰 작은 화면으로 연결했습니다. 공개 프로젝트를 선택하면 read-only ProjectTree가 프로젝트 단위 source metadata와 저장된 Terraform draft를 보여 주고, 댓글 패널은 PUBLIC 프로젝트에 한해 조회와 작성을 제공합니다. 또한 업로드 저장 경계에서 제공하는 sourceStorageProvider/sourceBinaryPersisted 상태를 표시해, metadata-only 모드와 실제 S3 writer 모드를 구분할 수 있게 했습니다.
```
