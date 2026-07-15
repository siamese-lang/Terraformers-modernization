# Modernization Cutoff

## 1. Purpose

This document defines where the current modernization PR must stop.

The branch already contains enough scope to demonstrate the intended direction:

```text
original Terraformers flow
  -> compatibility endpoints
  -> smaller backend contracts
  -> read-only frontend integration
  -> adapter validation path
```

Further feature additions should stop until this PR is validated and merged.

## 2. Current PR completion scope

The current PR is complete when the following contracts are present and validated by the standard workflow set.

### 2.1 Upload and analysis bridge

```text
POST /api/upload
  -> accepts architecture image multipart upload
  -> creates analysis job
  -> persists project metadata
  -> stores Terraform draft preview
```

Default validation mode remains local/stub:

```text
terraformers.storage.s3-writer-enabled=false
terraformers.analysis.mode=integrated-java
```

S3 writer mode exists as an optional adapter evidence path, not as a mandatory merge blocker.

### 2.2 Project metadata and project tree

```text
GET /api/projects
GET /api/projects/{projectId}
GET /api/projects/public
GET /api/project-tree
GET /api/project-tree/{projectId}
```

The tree remains read-only. Source nodes may expose metadata and persistence status, but not browser-downloadable object content.

### 2.3 Terraform draft preview

```text
GET /api/projects/{projectId}/terraform/main.tf
PUT /api/projects/{projectId}/terraform/main.tf
```

This is project-scoped draft content. It is not Terraform apply/destroy execution.

### 2.4 Public projects

```text
GET /api/public-projects
```

The adapter returns PUBLIC projects only and preserves original-style field aliases.

### 2.5 Public project comments

```text
GET  /api/projects/{projectId}/comments
POST /api/projects/{projectId}/comments
GET  /api/getProjectComments/{projectId}
POST /api/addProjectComment
```

Comments are minimal PUBLIC-project comments. Authentication/ownership, edit/delete, nested replies, and likes are not claimed.

### 2.6 S3 writer boundary

```text
UploadObjectStorageService
terraformers.storage.s3-writer-enabled=false -> metadata-only
terraformers.storage.s3-writer-enabled=true  -> S3 PutObject
```

The manual `S3 Writer Production Validation` workflow is an evidence path. It should not pull S3 reader, Bedrock, OpenSearch, or SQS into this PR.

## 3. Non-goals for this PR

Do not add the following to the current PR:

```text
S3 reader / source object download endpoint
browser image preview from S3
Bedrock production provider validation
OpenSearch retriever or embedding validation
SQS publisher validation
SQS log polling UI
Terraform run/destroy endpoints
Terraform tfstate endpoint
Cognito login restoration
browser AWS credential settings
project edit/delete
file create/rename/delete
likes/dislikes
nested comments
full original dashboard restoration
Kubernetes/EKS/GitOps infrastructure import
Terraform infrastructure import
Docker image publish pipeline
```

If any of these are needed later, they should be separate PRs with their own validation scope.

## 4. Validation gate before merge

Required before this PR can leave draft state:

```text
1. Frontend Import Verification
2. Backend Local Verification
3. Runtime Contract Verification
```

Optional evidence, not required to merge the base modernization PR:

```text
S3 Writer Production Validation
```

The S3 writer workflow proves real object persistence only when AWS bucket/IAM/OIDC setup is available. It should not delay the base PR if the local/stub path and contract tests are passing.

## 5. PR closure rule

After the three required workflows pass:

```text
mark PR ready for review
merge PR
start any further production adapter work in a new branch
```

Do not continue adding features to this branch after the required checks pass.

## 6. Next PR candidates

Only after this PR is merged, choose one next PR at a time:

```text
1. S3 reader/source object read contract
2. Bedrock provider validation
3. SQS publisher/log contract
4. OpenSearch retriever validation
5. Cognito/auth boundary
6. infrastructure import
```

Each next PR must have a smaller scope than the current one.

## 7. Portfolio explanation

```text
이번 현대화 PR의 종료 기준은 원본 Terraformers 전체 기능 복원이 아니라, 이미지 업로드에서 분석 job, 프로젝트 메타데이터, 프로젝트 트리, Terraform draft, 공개 프로젝트와 댓글까지 이어지는 핵심 제품 흐름을 검증 가능한 계약으로 정리하는 것입니다. S3 writer는 추가 evidence 경로로 마련하되, Bedrock·OpenSearch·SQS·Terraform 실행까지 한 번에 복원하지 않아 범위를 통제했습니다.
```
