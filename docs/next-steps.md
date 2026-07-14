# Next Steps

## 1. Current CI policy

The repository is still in a public baseline construction phase.

For now, GitHub Actions workflows are intentionally manual-only:

- Backend Maven Verification
- Backend Image Build Verification
- Runtime Contract Verification

Reason:

- backend adapter implementation is still being stabilized;
- deployment manifests are contract skeletons, not production overlays;
- repeated public red checks can make the project look broken rather than in-progress;
- deployment pipeline work should start only after the backend baseline passes local verification.

Re-enable push/PR triggers only after:

1. backend local verification passes;
2. runtime contract verification passes;
3. Docker image validation passes or is clearly documented as environment-pending;
4. selected original frontend import builds and has a clear browser smoke path;
5. manual GitHub Actions runs pass;
6. the README clearly states the validated baseline scope.

## 2. Validated baseline checkpoints

The project now has two evidence-grade local checkpoints.

### 2.1 Backend local/stub baseline

Validated in the local WSL environment:

- `mvn clean test` passed;
- backend package verification is available through `scripts/checks/backend-local-verification.sh`;
- `mvn spring-boot:run` started the default `local` profile after H2 was moved to runtime scope;
- `scripts/smoke/create-analysis-job.sh` created and fetched an analysis job successfully;
- smoke result returned `SUCCEEDED`, `provider=stub-integrated-java`, `resultObjectKey`, and non-empty `resultPreview`.

Evidence:

- [`docs/evidence/backend-local-smoke-2026-07-14.md`](evidence/backend-local-smoke-2026-07-14.md)

### 2.2 Runtime contract baseline

Validated in the local Git Bash environment:

- Kubernetes base rendered through `kubectl kustomize`;
- rendered base included ConfigMap, ServiceAccount, Deployment, and Service;
- rendered base did not include placeholder Secret resources;
- public base did not include account-specific IAM role ARNs or 12-digit account-like identifiers;
- Terraform runtime contract passed `terraform fmt -check`, `terraform validate`, and example `terraform plan`.

Evidence:

- [`docs/evidence/runtime-contract-verification-2026-07-14.md`](evidence/runtime-contract-verification-2026-07-14.md)

## 3. Deferred checkpoint: Docker image validation

Docker image validation remains useful, but it is not currently a blocker for frontend stabilization or adapter design work.

Current status:

- Docker is not installed in the current local environment;
- image validation is deferred until Docker Desktop / WSL integration is ready;
- Maven tests, local API smoke, and runtime contract verification should remain the current evidence baseline.

Run Docker image build later with:

```bash
RUN_DOCKER_BUILD=true bash scripts/checks/backend-local-verification.sh
```

Expected result:

```text
[backend] building Docker image
[backend] local verification completed
```

If Docker build fails later, isolate it as an image packaging/runtime issue, not a Maven test, local API smoke, or runtime contract issue.

## 4. Frontend correction

The temporary browser smoke screen that was created under `frontend/` has been removed from the main frontend path.

Reason:

- it was a newly created diagnostic UI, not the original Terraformers frontend;
- it made the repository look like a new frontend was being built;
- the project direction is to preserve and stabilize the original team-project UI flow where appropriate;
- frontend work should not replace backend/cloud modernization with a separate demo page.

The `frontend/` path should now be reserved for a selective, public-safe import from:

```text
siamese-lang/rdb-refactor/app/Terraformers-main/frontend
```

## 5. Completed: original frontend import inventory

Reference:

- [`docs/frontend-source-inventory.md`](frontend-source-inventory.md)
- [`docs/frontend-import-assessment.md`](frontend-import-assessment.md)
- [`docs/frontend-stabilization-plan.md`](frontend-stabilization-plan.md)

Inventory status:

- original source repository inspected through the GitHub connector;
- source groups identified for build files, auth/routing, API wrapper, upload/analysis, project tree/editor, public projects/comments, board layout, settings, and assets;
- first import pass identified;
- backend contract work created by frontend import is ordered;
- local clone of the old repository is not required.

## 6. Next priority: first original frontend import pass

Import the first public-safe source set from the original frontend, not a new diagnostic screen.

Recommended first pass:

```text
package.json
public/index.html
src/index.js
src/App.js
src/utils/api.js
src/utils/eventBus.js
src/utils/chatSupport.js
src/utils/visibility.js
src/components/AiChat.js
src/components/Dropzone.js
src/components/Modal.js
src/components/ProjectTree.js
src/components/EntryPage.js
src/components/ConfirmSignUpPage.js
minimum styles required for build
minimum assets required by selected components
```

Do not include in the first pass unless required by build:

```text
AppLayoutPreview.js
BoardContainer.js
src/api/board.js
Terraform run/destroy/tfstate active behavior
browser cloud-key settings behavior
old deployment workflows
```

Build stabilization rules:

1. Exclude `.env*`, `aws-exports*.js`, `node_modules`, `build`, old workflow files, and environment-specific values.
2. Replace missing binary assets with neutral placeholders only when necessary for build stabilization.
3. Keep broken controls only when they are clearly disabled or backed by a planned backend contract.
4. Remove only features that conflict with the project direction.

## 7. Backend contract bridge after first frontend import

Implement or adapt the core product contracts in this order:

1. Project metadata model.
2. Upload compatibility endpoint or frontend upload-to-analysis adaptation.
3. Analysis job status/result polling bridge.
4. Project tree read endpoint.
5. Terraform draft read/update as stored draft editing only.
6. Public project list and visibility update.
7. Comments for public projects.

Keep deferred until real integration exists:

- Terraform run/destroy/tfstate;
- real S3/SQS/Bedrock/OpenSearch browser behavior;
- browser-provided cloud key storage.

## 8. Adapter validation

Validate one production adapter at a time instead of enabling every runtime dependency at once.

Recommended order:

1. `S3_READER_ENABLED=true`
2. `S3_WRITER_ENABLED=true`
3. `BEDROCK_PROVIDER_ENABLED=true`
4. `BEDROCK_EMBEDDING_ENABLED=true`
5. `OPENSEARCH_RETRIEVER_ENABLED=true`
6. `ANALYSIS_SQS_PUBLISHER_ENABLED=true`

Use [`docs/runbooks/backend-analysis-adapter-failures.md`](runbooks/backend-analysis-adapter-failures.md) to isolate failures by adapter boundary.

## 9. Infrastructure import

After backend, runtime contract, and image validation, import Terraform in this order:

1. network/security group modules
2. ECR/RDS/S3/SQS/Secrets Manager/Cognito modules
3. IAM role and policy for backend runtime adapter access
4. External Secrets / SecretStore wiring
5. environment-specific Kubernetes overlays
6. image publish workflows
7. Terraform plan/apply workflows

Do not import the full private repository history.

## 10. Documentation updates

After each infrastructure/runtime change, update:

- `docs/validation.md`
- `docs/runbook.md`
- `docs/runbooks/*`
- `docs/evidence/*`
- `README.md`
