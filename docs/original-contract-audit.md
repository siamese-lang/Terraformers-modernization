# Original Contract Audit

## 1. Purpose

This audit compares selected original Terraformers contracts with the current modernization PR.

The purpose is to prevent scope drift:

```text
preserve what defines Terraformers
reimplement what needs a cleaner boundary
exclude what would turn this PR into a full rebuild
```

This is not a full source migration checklist. It is a cutoff tool for the current PR.

## 2. Upload contract

### 2.1 Original behavior

Original endpoint:

```text
POST /api/upload
```

Observed original behavior:

```text
multipart file upload
  -> resolve authenticated Cognito user
  -> create RDB project
  -> write architecture image to S3
  -> create project file metadata
  -> asynchronously call Bedrock service with bucket/key/projectId/queueUrl
  -> write generated Terraform code to S3
  -> create project file metadata for main.tf
  -> return projectId, file IDs, s3Url, queueUrl
```

### 2.2 Modernization behavior

Current endpoint:

```text
POST /api/upload
```

Current behavior:

```text
multipart file upload
  -> normalize project id
  -> UploadObjectStorageService returns source reference
  -> create analysis job
  -> upsert project metadata
  -> store project-scoped Terraform draft from analysis preview
  -> return analysis/upload response
```

### 2.3 Decision

```text
Endpoint name: reused
Multipart file field: reused
S3 write: reimplemented as isolated writer boundary
Cognito owner resolution: deferred
Bedrock async call: deferred
SQS queue URL response: excluded from this PR
Terraform code S3 write: replaced by DB-backed draft for this PR
project_files tree persistence: deferred
```

Reason: original upload is a valid product flow reference, but too coupled for the current modernization PR.

## 3. Public project list contract

### 3.1 Original behavior

Original endpoint:

```text
GET /api/public-projects
```

Original response shape included:

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

The original implementation could derive `imageUrl` from representative image S3 metadata.

### 3.2 Modernization behavior

Current endpoint:

```text
GET /api/public-projects
```

Current response preserves:

```text
projectId/id
projectName/name
visibility
isPrivate
source metadata
projectTreeApiPath
terraformDraftApiPath
```

Current intentional placeholders:

```text
imageUrl=null
description=null
```

### 3.3 Decision

```text
Endpoint name: reused
Core aliases: reused
PUBLIC-only filtering: preserved
imageUrl: deferred until S3 reader/public object contract exists
description: deferred until project description contract exists
```

Reason: public browsing is central to the original product, but public image serving is a separate storage read contract.

## 4. Project tree contract

### 4.1 Original behavior

Original project tree was tied to RDB numeric project IDs and `project_files` records. It also supported file operations such as create, rename, delete, and content read/write through S3-backed file metadata.

### 4.2 Modernization behavior

Current project tree is read-only:

```text
project root
  source metadata node
  terraform/main.tf draft node
```

### 4.3 Decision

```text
Project tree route: reused
Tree concept: reused
File operation controls: excluded from this PR
RDB project_files model: deferred
Read-only source/main.tf view: implemented
```

Reason: read-only tree supports the upload-to-draft product flow without expanding into full file manager restoration.

## 5. Terraform draft contract

### 5.1 Original behavior

Original generated Terraform code was written to S3 and represented as a `main.tf` project file. File read/update operations used file IDs and S3-backed project file metadata.

### 5.2 Modernization behavior

Current endpoints:

```text
GET /api/projects/{projectId}/terraform/main.tf
PUT /api/projects/{projectId}/terraform/main.tf
```

Draft content is project-scoped and DB-backed in this PR.

### 5.3 Decision

```text
main.tf preview concept: reused
S3-backed file content: deferred
Terraform apply/destroy: excluded
multi-file tree: deferred
```

Reason: the portfolio value at this stage is verifying draft generation and preview, not executing Terraform.

## 6. Comment contract

### 6.1 Original behavior

Original compatibility endpoints:

```text
POST /api/addProjectComment
GET  /api/getProjectComments/{projectId}
```

Original comments were tied to project boards, authenticated users, and comment service records.

### 6.2 Modernization behavior

Current endpoints:

```text
GET  /api/projects/{projectId}/comments
POST /api/projects/{projectId}/comments
GET  /api/getProjectComments/{projectId}
POST /api/addProjectComment
```

Current behavior:

```text
PUBLIC project -> list/create comments
PRIVATE project -> 403
missing project -> 404
blank content -> 400
optional userEmail -> anonymous fallback
```

### 6.3 Decision

```text
Endpoint names: reused
Comment concept: reused
PUBLIC-only guard: modernized
Authenticated ownership: deferred
edit/delete/nested replies/likes: excluded
```

Reason: comments support public project feedback, but full board behavior is not necessary for the current PR.

## 7. S3 writer validation contract

### 7.1 Original behavior

Original upload wrote the architecture image to S3 directly inside the upload controller.

### 7.2 Modernization behavior

Current S3 write is behind:

```text
UploadObjectStorageService
```

Modes:

```text
s3-writer-enabled=false -> metadata-only source reference
s3-writer-enabled=true  -> S3 PutObject
```

A manual workflow validates:

```text
/api/upload
  -> response.storageProvider=s3
  -> response.binaryPersisted=true
  -> response.sourceETag non-empty
  -> aws s3api head-object succeeds
```

### 7.3 Decision

```text
Actual S3 write capability: preserved in concept
Implementation location: changed
Validation style: added
S3 reader/public image serving: deferred
```

Reason: a separate writer boundary makes real AWS validation possible without enabling unrelated adapters.

## 8. Explicitly excluded original contracts

These original or adjacent behaviors should not be restored in this PR:

```text
/api/terraform/run/{projectId}
/api/terraform/destroy/{projectId}
/api/terraform/tfstate/{projectId}
/api/terraform/logs
/api/bedrock/logs
/api/files/{projectId}/{codeId}/content
/api/createFolder
/api/deleteNode
/api/rename-node
/api/update-terraform-code/{nodeId}
/api/getProjectInfrastructureImage/{projectId}
```

Reason: these require separate validated boundaries for S3 reader, Bedrock, SQS, Terraform execution, file ownership, and auth.

## 9. Required fixes before merge

No additional product features should be added before merge.

Required actions:

```text
1. Run Frontend Import Verification.
2. Run Backend Local Verification.
3. Run Runtime Contract Verification.
4. Confirm PR docs clearly describe source reuse/reimplementation/exclusions.
5. Keep S3 Writer Production Validation as optional evidence.
```

If any required workflow fails, fix only the failing contract. Do not add new product scope while fixing CI.

## 10. Summary

Current PR classification:

```text
Original Terraformers contract modernization, not full source migration.
```

What is preserved:

```text
product flow
selected endpoint names
public project/comment compatibility
upload-to-analysis-to-draft path
```

What is changed:

```text
runtime boundaries
storage abstraction
project metadata model
draft storage model
validation approach
```

What is intentionally postponed:

```text
authenticated full dashboard
S3 reader/public image serving
Bedrock/OpenSearch/SQS production adapters
Terraform execution
authenticated file manager behavior
```
