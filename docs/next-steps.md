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

The `frontend/` path is reserved for a selective, public-safe import from:

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
- backend contract work created by frontend import is ordered;
- local clone of the old repository is not required.

## 6. Completed: first original frontend import pass

Reference:

- [`docs/frontend-first-import.md`](frontend-first-import.md)

Imported in this pass:

```text
frontend/package.json
frontend/public/index.html
frontend/src/index.js
frontend/src/App.js
frontend/src/awsConfig.js
frontend/src/components/EntryPage.js
frontend/src/components/ConfirmSignUpPage.js
frontend/src/utils/api.js
frontend/src/utils/eventBus.js
frontend/src/utils/chatSupport.js
frontend/src/utils/visibility.js
frontend/src/index.css
frontend/src/styles/login.css
frontend/.env.example
scripts/checks/frontend-import-verification.sh
```

This is the original frontend's routing/auth/API foundation, not the full UI import.

Intentional deferrals:

```text
AiChat.js
Dropzone.js
Modal.js
ProjectTree.js
Monaco editor rendering
Project tree/editor endpoints
Public projects/comments
Terraform run/destroy/tfstate active behavior
browser cloud-key settings behavior
AppLayoutPreview / BoardContainer / board API
```

Local verification:

```bash
bash scripts/checks/frontend-import-verification.sh
```

If this build fails, fix this import boundary before importing `AiChat` or `ProjectTree`.

## 7. Next priority: upload/analysis UI import pass

Next pass should import the original upload-to-analysis surface in a controlled way:

1. `AiChat.js`;
2. `Dropzone.js`;
3. `Modal.js`;
4. required upload/chat/editor assets;
5. required dependencies such as Monaco, dropzone, SweetAlert2, loaders, and icons;
6. adaptation from legacy queue URL browser polling to analysis-job status/result polling.

Rules:

- do not recreate a separate diagnostic frontend;
- do not activate Terraform run/destroy/tfstate controls yet;
- do not import browser cloud-key settings behavior;
- if a button is product-valid but backend-missing, classify it as backend contract work instead of deleting it.

## 8. Backend contract bridge after frontend import

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

## 9. Adapter validation

Validate one production adapter at a time instead of enabling every runtime dependency at once.

Recommended order:

1. `S3_READER_ENABLED=true`
2. `S3_WRITER_ENABLED=true`
3. `BEDROCK_PROVIDER_ENABLED=true`
4. `BEDROCK_EMBEDDING_ENABLED=true`
5. `OPENSEARCH_RETRIEVER_ENABLED=true`
6. `ANALYSIS_SQS_PUBLISHER_ENABLED=true`

Use [`docs/runbooks/backend-analysis-adapter-failures.md`](runbooks/backend-analysis-adapter-failures.md) to isolate failures by adapter boundary.

## 10. Infrastructure import

After backend, runtime contract, and image validation, import Terraform in this order:

1. network/security group modules
2. ECR/RDS/S3/SQS/Secrets Manager/Cognito modules
3. IAM role and policy for backend runtime adapter access
4. External Secrets / SecretStore wiring
5. environment-specific Kubernetes overlays
6. image publish workflows
7. Terraform plan/apply workflows

Do not import the full private repository history.

## 11. Documentation updates

After each infrastructure/runtime change, update:

- `docs/validation.md`
- `docs/runbook.md`
- `docs/runbooks/*`
- `docs/evidence/*`
- `README.md`
