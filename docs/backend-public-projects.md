# Backend Public Project Compatibility Contract

## 1. Purpose

This pass bridges the original Terraformers public project list entry point onto the current project metadata model.

It does not restore the full board, comment, like, edit, delete, or sharing surface. The compatibility endpoint is intentionally read-only and only returns projects whose visibility is `PUBLIC`.

## 2. Source contract observed

The original backend exposed:

```text
GET /api/public-projects
```

The response shape was a list of map-like objects with fields such as:

```text
projectId
id
projectName
name
visibility
isPrivate
imageUrl
description
```

In the original implementation, `imageUrl` could be built from a representative S3 object. The modernization backend has not yet validated real binary upload persistence through the S3 writer, so this pass does not claim a working public image URL.

## 3. Current endpoint

```text
GET /api/public-projects
```

The endpoint is a thin adapter over:

```text
GET /api/projects/public
visibility=PUBLIC
```

Private projects are not returned.

## 4. Current response fields

```text
projectId
id
projectName
name
visibility
isPrivate
imageUrl
description
originalFilename
contentType
uploadSizeBytes
sourceBucket
sourceKey
latestAnalysisJobId
latestResultObjectKey
terraformDraftUpdatedAt
createdAt
updatedAt
projectTreeApiPath
terraformDraftApiPath
```

Compatibility aliases are provided so the original frontend-style code can use either `projectId`/`projectName` or `id`/`name`.

Current intentional placeholders:

```text
imageUrl=null
description=null
```

These fields remain null until their backend contracts exist. `sourceBucket` and `sourceKey` are metadata references, not a claim that the browser can fetch the uploaded binary object.

## 5. Verification

Covered by `ProjectMetadataControllerTest`:

```text
POST /api/upload private project
POST /api/upload second project
PATCH /api/projects/{projectId}/visibility PUBLIC
GET /api/public-projects
  -> returns only PUBLIC project
  -> returns original compatibility aliases
  -> returns project tree and Terraform draft API paths
```

Run through GitHub Actions:

```text
Backend Local Verification
```

## 6. Portfolio explanation

```text
기존 Terraformers의 공개 프로젝트 목록 진입점인 `/api/public-projects`를 새 프로젝트 메타데이터 모델 위에 조회 전용 호환 엔드포인트로 연결했습니다. 공개 여부는 `ProjectVisibility.PUBLIC`인 프로젝트만 반환하도록 제한했고, 원본 프론트가 기대하던 `projectId/id`, `projectName/name`, `isPrivate` 필드를 함께 제공했습니다. 다만 실제 S3 이미지 공개 URL, 댓글, 좋아요, 편집 기능은 아직 검증된 계약이 없으므로 null 또는 미구현 상태로 분리했습니다.
```
