# Frontend Public Projects Read-only Surface

## 1. Scope

This pass adds a small read-only public project list to the selected original frontend import path.

It preserves the modernization direction:

```text
/api/public-projects
  -> list PUBLIC projects
  -> select a project
  -> GET /api/project-tree/{projectId}
  -> inspect source metadata and stored Terraform draft
```

The component is intentionally smaller than the original `AiChat` dashboard surface.

## 2. Files

```text
frontend/src/components/PublicProjectsReadOnly.js
frontend/src/components/AiChat.js
frontend/src/styles/public-projects.css
frontend/src/utils/api.js
```

`/api/public-projects` was already included in the frontend auth-optional path list. This pass uses that existing API client behavior.

## 3. Behavior

The public projects panel:

```text
mounts
  -> GET /api/public-projects
  -> renders projectName/name and source metadata
  -> clicking a project updates selectedProjectId
  -> ProjectTreeReadOnly loads /api/project-tree/{projectId}
```

The project tree remains the existing read-only tree. Clicking `main.tf` still reads:

```text
GET /api/projects/{projectId}/terraform/main.tf
```

## 4. Explicit exclusions

The following original behaviors remain excluded:

```text
comments
likes/dislikes
project edit/delete
Terraform run/destroy/tfstate polling
browser AWS credential settings
public binary image preview through S3 URL
```

A public project list item may show upload metadata such as `originalFilename`, `sourceBucket`, and `sourceKey`, but this is not a claim that binary image persistence or public object serving is complete.

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
```

## 6. Portfolio explanation

```text
원본 Terraformers의 공개 프로젝트 탐색 흐름을 전체 대시보드나 댓글 기능까지 무리하게 복원하지 않고, 현재 검증된 `/api/public-projects`와 프로젝트 트리 계약에 맞춰 조회 전용 화면으로 연결했습니다. 공개 프로젝트를 선택하면 기존 read-only ProjectTree가 프로젝트 단위 source metadata와 저장된 Terraform draft를 보여 주므로, UI는 제품 흐름을 보조하고 핵심 검증은 백엔드 계약에 남겨 두었습니다.
```
