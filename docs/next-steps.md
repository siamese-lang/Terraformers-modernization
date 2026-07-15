# Next Steps

## 1. Current validation policy

Local workstation checks should be minimized because the current local environment is slow and disk constrained.

Use manual GitHub Actions first:

```text
Frontend Import Verification
Backend Local Verification
Runtime Contract Verification
```

Reference:

- [`docs/github-actions-verification.md`](github-actions-verification.md)

Local work should usually be limited to:

```bash
git pull --ff-only origin main
git status --short
```

Run browser smoke locally only when UI behavior must be inspected.

## 2. Validated baseline checkpoints

Current evidence-grade checkpoints:

```text
backend local/stub smoke
runtime contract verification
frontend selected original import build
upload/analysis UI build
manual GitHub Actions baseline
```

Evidence and reference docs:

- [`docs/evidence/backend-local-smoke-2026-07-14.md`](evidence/backend-local-smoke-2026-07-14.md)
- [`docs/evidence/runtime-contract-verification-2026-07-14.md`](evidence/runtime-contract-verification-2026-07-14.md)
- [`docs/evidence/frontend-first-import-verification-2026-07-14.md`](evidence/frontend-first-import-verification-2026-07-14.md)
- [`docs/evidence/frontend-upload-analysis-build-2026-07-15.md`](evidence/frontend-upload-analysis-build-2026-07-15.md)
- [`docs/github-actions-verification.md`](github-actions-verification.md)

## 3. Completed: original frontend import boundary

The temporary diagnostic frontend has been removed. The `frontend/` path is reserved for a selective, public-safe import from:

```text
siamese-lang/rdb-refactor/app/Terraformers-main/frontend
```

Reference:

- [`docs/frontend-source-inventory.md`](frontend-source-inventory.md)
- [`docs/frontend-import-assessment.md`](frontend-import-assessment.md)
- [`docs/frontend-stabilization-plan.md`](frontend-stabilization-plan.md)
- [`docs/frontend-first-import.md`](frontend-first-import.md)

## 4. Completed: upload / analysis UI bridge

The source-derived upload UI preserves the original product direction:

```text
chat-style architecture image selection
  -> POST /api/upload
  -> source reference or persisted source object
  -> analysis job creation
  -> GET /api/analysis/jobs/{id}
  -> Terraform draft preview
```

Reference:

- [`docs/frontend-upload-analysis-import.md`](frontend-upload-analysis-import.md)
- [`docs/backend-upload-compatibility.md`](backend-upload-compatibility.md)
- [`docs/backend-upload-binary-persistence.md`](backend-upload-binary-persistence.md)

Important boundary:

- `/api/upload` compatibility exists;
- upload metadata is captured;
- local/test mode remains metadata-only by default;
- S3 writer mode exists behind `terraformers.storage.s3-writer-enabled=true`;
- browser-visible SQS queue URL polling is not carried forward.

## 5. Completed: project metadata contract

Project metadata is the backend bridge for project tree, public project, comment, Terraform draft, and source persistence metadata.

Current flow:

```text
POST /api/upload
  -> storage boundary returns sourceBucket/sourceKey/provider/persistence status
  -> create analysis job
  -> upsert project metadata
```

Current endpoints:

```text
GET   /api/projects
GET   /api/projects/{projectId}
GET   /api/projects/public
PATCH /api/projects/{projectId}/visibility
```

Reference:

- [`docs/backend-project-metadata.md`](backend-project-metadata.md)

## 6. Completed: project tree read endpoint

A read-only project tree contract supports the original frontend's `ProjectTree` shape without enabling unsupported run/destroy/edit/delete controls.

Current endpoints:

```text
GET /api/project-tree
GET /api/project-tree/{projectId}
```

Current response shape:

```text
project root
  source
    uploaded image metadata node
  terraform
    main.tf stored draft node
```

Reference:

- [`docs/backend-project-tree.md`](backend-project-tree.md)

Important boundary:

- tree is read-only in this pass;
- source file node is metadata-oriented;
- `main.tf` points to the project draft endpoint;
- Terraform run/destroy/tfstate, rename, file create/delete, and full draft edit UI remain deferred.

## 7. Completed: frontend ProjectTree read-only import

The frontend renders a controlled read-only Project Tree beside the chat/upload flow.

Current flow:

```text
POST /api/upload
  -> analysis job result
  -> selected projectId
  -> GET /api/project-tree/{projectId}
  -> render source/main.tf nodes
  -> click main.tf
  -> GET /api/projects/{projectId}/terraform/main.tf
```

Current frontend files:

```text
frontend/src/components/ProjectTreeReadOnly.js
frontend/src/components/AiChat.js
frontend/src/utils/api.js
frontend/src/index.css
```

Reference:

- [`docs/frontend-project-tree-readonly.md`](frontend-project-tree-readonly.md)

Important boundary:

- original `ProjectTree.js` was not copied wholesale;
- run/destroy/rename/delete/create controls are not active;
- clicking `main.tf` previews the stored project draft `content`;
- source file node remains metadata-oriented until object read/download is validated.

## 8. Completed: stored Terraform draft read/update endpoint

Terraform draft handling is project-scoped instead of relying on raw analysis job preview reads.

Current endpoints:

```text
GET  /api/projects/{projectId}/terraform/main.tf
PUT  /api/projects/{projectId}/terraform/main.tf
```

Current flow:

```text
POST /api/upload
  -> analysis resultPreview
  -> store as project terraformDraft
GET /api/projects/{projectId}/terraform/main.tf
  -> return stored content
PUT /api/projects/{projectId}/terraform/main.tf
  -> update stored content and draft timestamp
```

Reference:

- [`docs/backend-terraform-draft.md`](backend-terraform-draft.md)

Important boundary:

- draft storage is DB-backed in this pass;
- Terraform apply/destroy remains deferred;
- multi-file draft tree remains future work.

## 9. Completed: public project list compatibility

The original public project list entry point exists as a thin read-only adapter over the current project metadata model.

Current endpoint:

```text
GET /api/public-projects
```

Current backend mapping:

```text
GET /api/projects/public
visibility=PUBLIC
  -> compatibility aliases for projectId/id and projectName/name
  -> source persistence metadata
```

Current frontend flow:

```text
GET /api/public-projects
  -> render read-only public project list
  -> select a public project
  -> GET /api/project-tree/{projectId}
  -> read source metadata and stored main.tf draft
```

Current files:

```text
backend/src/main/java/com/terraformers/modernization/project/PublicProjectCompatibilityController.java
backend/src/main/java/com/terraformers/modernization/project/PublicProjectResponse.java
frontend/src/components/PublicProjectsReadOnly.js
frontend/src/styles/public-projects.css
```

Reference:

- [`docs/backend-public-projects.md`](backend-public-projects.md)
- [`docs/frontend-public-projects-readonly.md`](frontend-public-projects-readonly.md)

Important boundary:

- private projects are not returned;
- `imageUrl` and `description` remain null until real contracts exist;
- likes, edit/delete, and share workflows remain deferred;
- browser cloud credential settings are still not restored.

## 10. Completed: public project comments

PUBLIC projects have a minimal comment contract and a small frontend comment surface.

Current modern endpoints:

```text
GET  /api/projects/{projectId}/comments
POST /api/projects/{projectId}/comments
```

Original frontend compatibility endpoints:

```text
GET  /api/getProjectComments/{projectId}
POST /api/addProjectComment
```

Current backend behavior:

```text
PUBLIC project -> list/create comments
PRIVATE project -> 403
missing project -> 404
blank content -> 400
```

Current frontend flow:

```text
select public project
  -> GET /api/getProjectComments/{projectId}
  -> render comments
  -> POST /api/addProjectComment
  -> refresh comments
```

Reference:

- [`docs/backend-public-comments.md`](backend-public-comments.md)
- [`docs/frontend-public-comments.md`](frontend-public-comments.md)

Important boundary:

- comments are allowed only for PUBLIC projects;
- user ownership and authentication are not claimed yet;
- comment edit/delete, likes/dislikes, nested replies, and board dashboard restoration remain deferred.

## 11. Completed: upload storage boundary and S3 writer mode

The upload path now has an explicit storage boundary that supports default metadata-only behavior and opt-in S3 writer behavior.

Current backend flow:

```text
POST /api/upload
  -> UploadObjectStorageService
  -> metadata-only source reference when s3-writer-enabled=false
  -> S3 PutObject when s3-writer-enabled=true
  -> analysis job receives returned sourceBucket/sourceKey
  -> project metadata records sourceStorageProvider/sourceBinaryPersisted/sourceETag
```

Current response fields:

```text
storageProvider
binaryPersisted
storageETag
sourceBucket
sourceKey
```

Current project metadata fields:

```text
sourceStorageProvider
sourceBinaryPersisted
sourceETag
```

Current files:

```text
backend/src/main/java/com/terraformers/modernization/storage/StoredUploadObject.java
backend/src/main/java/com/terraformers/modernization/storage/UploadObjectStorageService.java
backend/src/main/java/com/terraformers/modernization/storage/UploadStorageException.java
backend/src/test/java/com/terraformers/modernization/storage/UploadObjectStorageServiceTest.java
```

Reference:

- [`docs/backend-upload-binary-persistence.md`](backend-upload-binary-persistence.md)
- [`docs/backend-upload-compatibility.md`](backend-upload-compatibility.md)

Important boundary:

- default local/test mode still does not require AWS credentials;
- S3 writer mode is implemented but still needs real AWS environment validation before being described as production-proven evidence;
- S3 reader, Bedrock, OpenSearch, and SQS publisher remain separate adapter boundaries;
- browser cloud credential settings are still not restored.

## 12. Next priority: S3 writer production validation evidence

The next work should validate the S3 writer boundary against a real configured bucket without enabling unrelated production adapters.

Recommended scope:

```text
terraformers.storage.s3-writer-enabled=true
terraformers.upload.source-bucket=<real bucket>
POST /api/upload
  -> verify S3 PutObject succeeds
  -> verify response binaryPersisted=true
  -> verify project metadata sourceBinaryPersisted=true
  -> verify analysis provider remains local/stub unless explicitly changed
```

Rules:

- do not enable every production adapter at once;
- keep local/test stub behavior intact;
- do not move to S3 read or Bedrock provider until S3 write evidence is stable;
- do not expose browser cloud credential settings.

## 13. Remaining backend product contracts

Implement in this order:

1. S3 writer production validation evidence.
2. S3 reader/source object read validation.
3. Bedrock provider validation.
4. OpenSearch retriever and embedding validation.
5. SQS publisher validation.
6. Docker image validation, if needed.
7. Infrastructure import.

Keep deferred until real integration exists:

- Terraform run/destroy/tfstate;
- full S3/SQS/Bedrock/OpenSearch browser behavior;
- browser-provided cloud key storage.

## 14. Adapter validation order

Validate one production adapter at a time instead of enabling every runtime dependency at once:

```text
S3_WRITER_ENABLED=true
S3_READER_ENABLED=true
BEDROCK_PROVIDER_ENABLED=true
BEDROCK_EMBEDDING_ENABLED=true
OPENSEARCH_RETRIEVER_ENABLED=true
ANALYSIS_SQS_PUBLISHER_ENABLED=true
```

Use [`docs/runbooks/backend-analysis-adapter-failures.md`](runbooks/backend-analysis-adapter-failures.md) to isolate failures by adapter boundary.

## 15. Infrastructure import

After backend, runtime contract, frontend import, image validation, and adapter validation are stable, import Terraform in this order:

1. network/security group modules;
2. ECR/RDS/S3/SQS/Secrets Manager/Cognito modules;
3. IAM role and policy for backend runtime adapter access;
4. External Secrets / SecretStore wiring;
5. environment-specific Kubernetes overlays;
6. image publish workflows;
7. Terraform plan/apply workflows.

Do not import the full private repository history.
