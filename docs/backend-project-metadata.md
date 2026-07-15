# Backend Project Metadata Contract

## 1. Purpose

Project metadata is the backend bridge between the original Terraformers upload flow and later project tree, public project, comment, Terraform draft editing, and source object persistence features.

This model does not claim that the complete original project-management surface has been restored. It provides the minimum persisted project record needed after upload analysis.

## 2. Current model

A project is keyed by `projectId` and stores:

```text
projectId
displayName
visibility
latestAnalysisJobId
latestResultObjectKey
terraformDraft
terraformDraftUpdatedAt
sourceBucket
sourceKey
sourceStorageProvider
sourceBinaryPersisted
sourceETag
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

`sourceStorageProvider/sourceBinaryPersisted/sourceETag` describe whether the uploaded architecture image is only represented by metadata or was actually persisted through the S3 writer boundary.

## 3. Upload integration

`POST /api/upload` now performs these actions:

```text
multipart image upload
  -> UploadObjectStorageService
  -> source reference or persisted S3 object
  -> create analysis job
  -> upsert project metadata
```

Default local/test behavior remains metadata-only. S3 object persistence is enabled only when the S3 writer adapter is explicitly turned on.

Reference:

```text
docs/backend-upload-binary-persistence.md
```

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
  -> sourceStorageProvider/sourceBinaryPersisted are exposed
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
업로드된 아키텍처 이미지를 단순 분석 요청으로만 처리하지 않고, 프로젝트 단위 메타데이터로 저장되도록 백엔드 계약을 확장했습니다. 또한 sourceBucket/sourceKey뿐 아니라 sourceStorageProvider와 sourceBinaryPersisted를 함께 저장해, 로컬 metadata-only 모드와 실제 S3 writer 모드를 구분할 수 있게 했습니다. 이를 통해 이후 프로젝트 트리, 공개 프로젝트 목록, 댓글, Terraform 초안 편집 기능이 특정 분석 작업이 아니라 프로젝트 기준으로 연결될 수 있게 했습니다.
```
