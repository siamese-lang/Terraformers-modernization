# Source Reuse Plan

## 1. Purpose

This document fixes how the modernization branch uses the original Terraformers codebase.

The goal is not to rebuild a similar new application from scratch. The goal is to preserve the original Terraformers product flow while replacing tightly coupled runtime code with smaller, testable backend contracts.

Fixed product flow:

```text
architecture image upload
  -> component analysis
  -> Terraform draft generation
  -> project metadata persistence
  -> project tree / main.tf preview
  -> public project browsing / comments
```

## 2. Source repositories

Modernization target:

```text
siamese-lang/Terraformers-modernization
```

Original reference:

```text
siamese-lang/rdb-refactor
```

Primary original backend reference:

```text
app/Terraformers-main/backend/mini/src/main/java/com/amazoonS3/mini/controller/FileUploadController.java
app/Terraformers-main/backend/mini/src/main/java/com/amazoonS3/mini/controller/ProjectController.java
```

Primary original frontend reference:

```text
app/Terraformers-main/frontend/src/components/AiChat.js
```

## 3. Reuse policy

### 3.1 Reuse as product contract

Reuse these from the original project as compatibility contracts:

```text
endpoint names
request entry points
major response field aliases
frontend-visible user flow
project/public/comment terminology
```

Examples:

```text
POST /api/upload
GET  /api/public-projects
GET  /api/project-tree/{projectId}
GET  /api/getProjectComments/{projectId}
POST /api/addProjectComment
```

These names matter because they preserve the identity of the original Terraformers service and keep the source-derived frontend understandable.

### 3.2 Reimplement as modernization boundary

Reimplement these instead of copying the original controller logic directly:

```text
upload storage boundary
analysis job creation
project metadata persistence
Terraform draft persistence
public project adapter
comment persistence
runtime validation workflows
```

Reason: the original implementation combines many runtime responsibilities in a small number of controllers. The modernization branch should separate those responsibilities into testable contracts.

Original `/api/upload` combines:

```text
Cognito-authenticated user resolution
RDB project creation
S3 image PutObject
project file metadata creation
asynchronous Bedrock service call
SQS queue URL handling
Terraform code S3 write
project file metadata creation for main.tf
```

The modernization branch intentionally splits this into:

```text
/upload compatibility controller
  -> upload storage service
  -> analysis job service
  -> project metadata service
  -> Terraform draft contract
```

### 3.3 Exclude from this PR

Do not restore these in the current PR even if they exist in the original project:

```text
Terraform run/destroy/tfstate endpoints
browser AWS credential settings
SQS log polling in the browser
Bedrock provider production mode
OpenSearch retriever production mode
S3 reader / browser-fetchable image preview
project edit/delete UI
file create/rename/delete UI
likes/dislikes
nested comments
full dashboard restoration
```

These may be future work only after the current PR is merged and validated.

## 4. Feature-by-feature decision table

| Area | Original reference | Current decision | Reason |
|---|---|---|---|
| `/api/upload` endpoint name | Reuse | Keep endpoint | Original frontend entry point |
| Multipart file request | Reuse | Keep `file` form field | Compatibility and simple smoke testing |
| Authenticated upload owner | Defer | Not restored in this PR | Avoid Cognito coupling before auth boundary is validated |
| S3 image write | Reimplement | `UploadObjectStorageService` | Keep writer boundary independently testable |
| S3 key format | Adapt | Use deterministic project/prefix/date source key | Avoid opaque UUID-only key while preserving bucket/key source reference |
| Project metadata | Reimplement | `ProjectMetadataService` | Current branch uses simplified project model |
| `project_files` tree model | Defer | Metadata-oriented read-only tree | Full file management would expand scope too much |
| Bedrock analysis call | Defer | Stub/local analysis remains default | Avoid enabling Bedrock/SQS/OpenSearch together |
| Terraform draft | Reimplement | DB-backed project-scoped `main.tf` draft | Small contract for preview and edit without S3 reader |
| Public project list | Reuse contract, reimplement code | `/api/public-projects` adapter | Keep original frontend aliases, avoid full board restoration |
| Comments | Reuse contract, reimplement code | Public-only comments | Keep compatibility endpoints with smaller behavior |
| Likes/dislikes | Exclude | Not implemented | Not central to modernization goal |
| Terraform run/destroy | Exclude | Not implemented | High-risk scope expansion |
| S3 writer validation | New | Manual evidence workflow | Supports operational validation without enabling all adapters |

## 5. Completion rule

For this PR, a feature is complete only when it satisfies one of these conditions:

```text
1. It preserves an original endpoint or frontend-visible contract already selected for this PR.
2. It replaces an original tightly coupled behavior with a smaller verified backend boundary.
3. It documents why an original behavior is intentionally excluded.
```

A feature should not be added merely because it existed in the original project.

## 6. Portfolio explanation

```text
Terraformers 현대화 작업에서는 원본 프로젝트의 핵심 사용자 흐름과 API 명칭을 기준으로 삼되, 원본 컨트롤러를 그대로 복사하지 않았습니다. 원본 `/api/upload`는 S3 업로드, RDB 프로젝트 생성, Bedrock 호출, SQS 로그, Terraform 코드 저장까지 한 흐름에 묶여 있었기 때문에, 현대화 버전에서는 업로드 저장소, 분석 job, 프로젝트 메타데이터, Terraform draft를 분리된 계약으로 재구성했습니다. 반대로 `/api/public-projects`, `/api/addProjectComment`, `/api/getProjectComments/{projectId}`처럼 프론트 호환성에 중요한 진입점은 원본 명칭을 유지했습니다.
```
