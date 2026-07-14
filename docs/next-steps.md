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

The source-derived upload UI now preserves the original product direction:

```text
chat-style architecture image selection
  -> POST /api/upload
  -> analysis job creation
  -> GET /api/analysis/jobs/{id}
  -> Terraform draft preview
```

Reference:

- [`docs/frontend-upload-analysis-import.md`](frontend-upload-analysis-import.md)
- [`docs/backend-upload-compatibility.md`](backend-upload-compatibility.md)

Important boundary:

- `/api/upload` compatibility exists;
- upload metadata is captured;
- analysis job creation is wired;
- real binary persistence through S3 writer remains future work;
- browser-visible SQS queue URL polling is not carried forward.

## 5. Completed: project metadata contract

Project metadata now exists as the backend bridge for future project tree, public project, comment, and Terraform draft editing features.

Current flow:

```text
POST /api/upload
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

A read-only project tree contract now supports the original frontend's `ProjectTree` shape without enabling unsupported run/destroy/edit/delete controls.

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
    main.tf latest result node
```

Reference:

- [`docs/backend-project-tree.md`](backend-project-tree.md)

Important boundary:

- tree is read-only in this pass;
- source file node is metadata-only;
- `main.tf` points to the latest analysis job/result object metadata;
- Terraform run/destroy/tfstate, rename, file create/delete, and draft edit APIs remain deferred.

## 7. Completed: frontend ProjectTree read-only import

The frontend now renders a controlled read-only Project Tree beside the chat/upload flow.

Current flow:

```text
POST /api/upload
  -> analysis job result
  -> selected projectId
  -> GET /api/project-tree/{projectId}
  -> render source/main.tf nodes
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
- clicking `main.tf` previews the latest analysis job `resultPreview`;
- source file node remains metadata-only until binary object read/persistence is implemented.

## 8. Next priority: stored Terraform draft read/update endpoint

The next backend product contract should make Terraform draft handling explicit instead of relying on `GET /api/analysis/jobs/{id}` for preview.

Recommended contract:

```text
GET  /api/projects/{projectId}/terraform/main.tf
PUT  /api/projects/{projectId}/terraform/main.tf
```

Initial scope:

```text
read latest generated draft
persist edited draft in local/test storage model
return draft metadata and revision timestamp
```

Rules:

- do not claim full S3 object persistence until S3 writer is enabled and validated;
- do not activate Terraform run/destroy controls;
- make edited draft storage separate from generated analysis result metadata;
- keep browser cloud credential settings disabled.

## 9. Remaining backend product contracts

Implement in this order:

1. Stored Terraform draft read/update endpoint.
2. Public project list compatibility endpoint if the old frontend requires `/api/public-projects`.
3. Comments for public projects.
4. Real upload binary persistence through S3 writer.
5. Production adapter validation one boundary at a time.

Keep deferred until real integration exists:

- Terraform run/destroy/tfstate;
- real S3/SQS/Bedrock/OpenSearch browser behavior;
- browser-provided cloud key storage.

## 10. Adapter validation order

Validate one production adapter at a time instead of enabling every runtime dependency at once:

```text
S3_READER_ENABLED=true
S3_WRITER_ENABLED=true
BEDROCK_PROVIDER_ENABLED=true
BEDROCK_EMBEDDING_ENABLED=true
OPENSEARCH_RETRIEVER_ENABLED=true
ANALYSIS_SQS_PUBLISHER_ENABLED=true
```

Use [`docs/runbooks/backend-analysis-adapter-failures.md`](runbooks/backend-analysis-adapter-failures.md) to isolate failures by adapter boundary.

## 11. Infrastructure import

After backend, runtime contract, frontend import, and image validation are stable, import Terraform in this order:

1. network/security group modules;
2. ECR/RDS/S3/SQS/Secrets Manager/Cognito modules;
3. IAM role and policy for backend runtime adapter access;
4. External Secrets / SecretStore wiring;
5. environment-specific Kubernetes overlays;
6. image publish workflows;
7. Terraform plan/apply workflows.

Do not import the full private repository history.
