# Backend Public Project Comments Contract

## 1. Purpose

This pass adds a minimal comment contract for PUBLIC projects.

It connects the original Terraformers public-project comment idea to the current modernization backend without restoring the old board, like/dislike, edit/delete, or browser credential behavior.

## 2. Scope

Current backend scope:

```text
PUBLIC project
  -> list comments
  -> create comment
```

A comment is project-scoped and stores:

```text
id
projectId
content
userEmail
createdAt
```

`userEmail` is optional in this pass. When it is omitted, the backend records `anonymous`.

## 3. Endpoints

### Modern project-scoped endpoints

```text
GET  /api/projects/{projectId}/comments
POST /api/projects/{projectId}/comments
```

POST request:

```json
{
  "content": "comment text",
  "userEmail": "optional@example.com"
}
```

POST response status:

```text
201 Created
```

### Original frontend compatibility endpoints

```text
GET  /api/getProjectComments/{projectId}
POST /api/addProjectComment
```

Compatibility POST request:

```json
{
  "projectId": "shared-architecture",
  "content": "comment text",
  "userEmail": "optional@example.com"
}
```

The compatibility POST returns the created comment response directly. It exists only to bridge the original frontend flow.

## 4. Visibility rule

Comments are allowed only for projects where:

```text
visibility=PUBLIC
```

Current behavior:

```text
missing project -> 404
PRIVATE project -> 403
blank content -> 400
```

This prevents a public comment surface from exposing or attaching data to private project records.

## 5. Verification

Covered by `ProjectCommentControllerTest`:

```text
POST /api/upload
PATCH /api/projects/{projectId}/visibility PUBLIC
POST /api/projects/{projectId}/comments
GET  /api/projects/{projectId}/comments
POST /api/addProjectComment
GET  /api/getProjectComments/{projectId}
PRIVATE project comment access returns 403
missing project comment access returns 404
blank comment content returns 400
```

Run through GitHub Actions:

```text
Backend Local Verification
```

## 6. Explicit exclusions

This pass does not implement:

- comment edit;
- comment delete;
- likes/dislikes;
- nested replies;
- authenticated user ownership;
- moderation workflow;
- board-style dashboard restoration.

Authentication can be added later after the runtime auth boundary is validated. Until then, comments are intentionally shallow and tied only to PUBLIC project visibility.

## 7. Portfolio explanation

```text
공개 프로젝트 목록을 단순 조회로 끝내지 않고, PUBLIC 프로젝트에 한정해 댓글을 조회·작성할 수 있는 백엔드 계약을 추가했습니다. 기존 Terraformers 프론트가 사용하던 `/api/getProjectComments/{projectId}`와 `/api/addProjectComment`도 호환 엔드포인트로 연결하되, 실제 계약은 프로젝트 단위의 `/api/projects/{projectId}/comments`로 정리했습니다. 비공개 프로젝트에는 댓글을 조회하거나 남길 수 없도록 제한해, 공개 범위와 사용자 상호작용의 경계를 분리했습니다.
```
