# Frontend Public Project Comments Pass

## 1. Scope

This pass extends the read-only public project surface with a minimal PUBLIC-project comment panel.

It keeps the frontend role narrow:

```text
GET /api/public-projects
  -> select public project
  -> GET /api/getProjectComments/{projectId}
  -> render comments
  -> POST /api/addProjectComment
  -> refresh comments
```

## 2. Current frontend files

```text
frontend/src/components/PublicProjectsReadOnly.js
frontend/src/styles/public-projects.css
```

`AiChat.js` still owns the selected project id and passes it to:

```text
PublicProjectsReadOnly
ProjectTreeReadOnly
```

That keeps the public list, comments, and read-only tree aligned on one selected PUBLIC project.

## 3. User-visible behavior

Current behavior:

```text
public project list loads from /api/public-projects
selecting a project loads comments
comments are shown with userEmail, createdAt, content
optional email + content form posts a comment
comments refresh after save
```

The form is available only after a public project is selected.

## 4. Compatibility decision

The frontend uses the original-style compatibility endpoints:

```text
GET  /api/getProjectComments/{projectId}
POST /api/addProjectComment
```

This is deliberate because the current pass is about preserving the source-derived public project flow while the backend owns the safer modern contract:

```text
GET  /api/projects/{projectId}/comments
POST /api/projects/{projectId}/comments
```

## 5. Explicit exclusions

This pass does not add:

- likes or dislikes;
- comment edit/delete;
- nested replies;
- board dashboard layout;
- authenticated comment ownership;
- project share/edit/delete controls;
- browser AWS credential settings.

## 6. Verification

Run through GitHub Actions:

```text
Frontend Import Verification
Backend Local Verification
```

Short browser smoke, only when UI inspection is necessary:

```text
create/upload project
mark project visibility PUBLIC through backend/API path
open frontend
select the public project
add a comment
verify it appears after save
```

Do not expand this into full dashboard restoration.

## 7. Portfolio explanation

```text
기존 Terraformers의 공개 프로젝트 댓글 흐름을 그대로 대시보드 전체로 복원하지 않고, 공개 프로젝트 목록 옆의 작은 댓글 패널로 제한했습니다. 프론트는 `/api/public-projects`로 공개 프로젝트를 선택하고, 호환 엔드포인트로 댓글을 조회·작성합니다. 좋아요, 수정, 삭제, 공유 편집은 아직 구현하지 않아 실제 백엔드 계약이 없는 기능을 UI에 먼저 노출하지 않았습니다.
```
