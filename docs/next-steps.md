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

## 6. Next priority: project tree read endpoint

Implement a minimal project tree read contract that can support the original frontend's `ProjectTree` import without pretending that full file editing is complete.

Recommended first contract:

```text
GET /api/project-tree/{projectId}
```

The first response should be derived from project metadata and latest analysis result:

```text
project root
  architecture image metadata
  generated Terraform draft metadata
```

Rules:

- do not activate Terraform run/destroy/tfstate controls yet;
- do not import browser cloud-key settings behavior;
- do not claim full S3-backed file tree until binary persistence and draft storage contracts are implemented;
- classify missing UI actions as backend contract work instead of deleting them silently.

## 7. Remaining backend product contracts

Implement in this order:

1. Project tree read endpoint.
2. Stored Terraform draft read/update endpoint.
3. Public project list compatibility endpoint if the old frontend requires `/api/public-projects`.
4. Comments for public projects.
5. Real upload binary persistence through S3 writer.
6. Production adapter validation one boundary at a time.

Keep deferred until real integration exists:

- Terraform run/destroy/tfstate;
- real S3/SQS/Bedrock/OpenSearch browser behavior;
- browser-provided cloud key storage.

## 8. Adapter validation order

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

## 9. Infrastructure import

After backend, runtime contract, frontend import, and image validation are stable, import Terraform in this order:

1. network/security group modules;
2. ECR/RDS/S3/SQS/Secrets Manager/Cognito modules;
3. IAM role and policy for backend runtime adapter access;
4. External Secrets / SecretStore wiring;
5. environment-specific Kubernetes overlays;
6. image publish workflows;
7. Terraform plan/apply workflows.

Do not import the full private repository history.
