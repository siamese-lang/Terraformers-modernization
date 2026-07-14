# Backend Project Metadata Contract

## 1. Purpose

Project metadata is the backend bridge between the original Terraformers upload flow and later project tree, public project, comment, and Terraform draft editing features.

This model does not claim that the complete original project-management surface has been restored. It provides the minimum persisted project record needed after upload analysis.

## 2. Current model

A project is keyed by `projectId` and stores:

```text
projectId
displayName
visibility
latestAnalysisJobId
latestResultObjectKey
sourceBucket
sourceKey
originalFilename
contentType
uploadSizeBytes
createdAt
updatedAt
```

Default visibility is:

```text
PRIVATE
```

## 3. Upload integration

`POST /api/upload` now performs two actions:

```text
multipart image upload metadata
  -> create analysis job
  -> upsert project metadata
```

The upload endpoint still uses the existing analysis job contract for analysis execution. Binary object persistence through a real S3 writer remains future work.

## 4. Endpoints

### Get all projects

```text
GET /api/projects
```

### Get one project

```text
GET /api/projects/{projectId}
```

Returns `404` when the project does not exist.

### Get public projects

```text
GET /api/projects/public
```

Returns projects where:

```text
visibility=PUBLIC
```

### Update project visibility

```text
PATCH /api/projects/{projectId}/visibility
Content-Type: application/json

{"visibility":"PUBLIC"}
```

Allowed values:

```text
PRIVATE
PUBLIC
```

## 5. Verification

Covered by `ProjectMetadataControllerTest`:

```text
POST /api/upload
  -> creates project metadata
  -> GET /api/projects/{projectId} returns latest job/source/upload metadata
  -> PATCH visibility changes PRIVATE/PUBLIC
  -> GET /api/projects/public lists public project
  -> missing project returns 404
```

Run through GitHub Actions:

```text
Backend Local Verification
```

## 6. Portfolio explanation

```text
업로드된 아키텍처 이미지를 단순 분석 요청으로만 처리하지 않고, 프로젝트 단위 메타데이터로 저장되도록 백엔드 계약을 확장했습니다. 이를 통해 이후 프로젝트 트리, 공개 프로젝트 목록, 댓글, Terraform 초안 편집 기능이 특정 분석 작업이 아니라 프로젝트 기준으로 연결될 수 있게 했습니다. 다만 실제 바이너리 객체 저장과 전체 프로젝트 파일 트리는 후속 단계로 분리해, 현재 구현 범위를 과장하지 않았습니다.
```
