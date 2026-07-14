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

1. `bash scripts/checks/backend-local-verification.sh` passes locally;
2. `bash scripts/checks/runtime-contract-verification.sh` passes locally;
3. manual GitHub Actions runs pass;
4. the README clearly states the validated baseline scope.

## 2. Immediate backend stabilization

The next priority is not deployment automation. Stabilize the backend baseline first.

Run backend verification:

```bash
bash scripts/checks/backend-local-verification.sh
```

Run runtime contract verification:

```bash
bash scripts/checks/runtime-contract-verification.sh
```

Run backend locally and execute the analysis job smoke script:

```bash
BASE_URL=http://localhost:8080 \
PROJECT_ID=project-smoke \
SOURCE_BUCKET=example-bucket \
SOURCE_KEY=uploads/architecture-diagram.png \
bash scripts/smoke/create-analysis-job.sh
```

The smoke script should confirm `SUCCEEDED`, `resultObjectKey`, and `resultPreview`.

If Maven, Docker, kustomize, Terraform, or smoke validation fails, fix that before importing more code.

## 3. Frontend stabilization after backend baseline

Frontend work should start only after the backend local/stub baseline is stable.

Purpose:

- do not rebuild the frontend;
- do not turn this into a frontend portfolio;
- stabilize the existing team-project UI enough to demonstrate backend/cloud improvements.

Planned checks:

1. Import public-safe frontend source.
2. Run `npm install` and build.
3. Fix signup black screen or post-signup route failure.
4. Fix main screen icons/buttons that do not route or trigger any action.
5. Align API base URL, Cognito config, Authorization header, and CORS/CloudFront assumptions.
6. Connect or hide controls for flows the backend can actually support.
7. Verify browser smoke flow:

```text
Open app
  -> sign up or sign in
  -> reach main screen
  -> create or open project flow
  -> upload/select architecture image
  -> create analysis job
  -> display status/result preview/result object key
```

Detailed scope is documented in [`docs/frontend-stabilization-plan.md`](frontend-stabilization-plan.md).

## 4. Runtime contract validation

The runtime deployment contract exists in:

- `infra/kubernetes/base/*`
- `infra/terraform/runtime-contract/*`
- `scripts/checks/runtime-contract-verification.sh`
- `.github/workflows/runtime-contract-verification.yml`
- `docs/deployment-runtime-contract.md`
- `docs/runtime-contract-verification.md`

Validation expectations:

- Kubernetes base renders ConfigMap, ServiceAccount, Deployment, and Service.
- Kubernetes base does not render `backend-secret.example.yaml`.
- Public base does not include account-specific IAM role ARNs.
- Example files use placeholders only.
- Terraform runtime contract validates and plans with `terraform.tfvars.example`.

Do not apply the example values to a real account. They are placeholders for contract validation.

## 5. Adapter validation

Validate one production adapter at a time instead of enabling every runtime dependency at once.

Recommended order:

1. `S3_READER_ENABLED=true`
2. `S3_WRITER_ENABLED=true`
3. `BEDROCK_PROVIDER_ENABLED=true`
4. `BEDROCK_EMBEDDING_ENABLED=true`
5. `OPENSEARCH_RETRIEVER_ENABLED=true`
6. `ANALYSIS_SQS_PUBLISHER_ENABLED=true`

Use [`docs/runbooks/backend-analysis-adapter-failures.md`](runbooks/backend-analysis-adapter-failures.md) to isolate failures by adapter boundary.

## 6. Infrastructure import

After backend, runtime contract, and minimum frontend smoke are stable, import Terraform in this order:

1. network/security group modules
2. ECR/RDS/S3/SQS/Secrets Manager/Cognito modules
3. IAM role and policy for backend runtime adapter access
4. External Secrets / SecretStore wiring
5. environment-specific Kubernetes overlays
6. image publish workflows
7. Terraform plan/apply workflows

Do not import the full private repository history.

## 7. Documentation updates

After each backend/frontend/infrastructure change, update:

- `docs/validation.md`
- `docs/runbook.md`
- `docs/runbooks/*`
- `docs/frontend-stabilization-plan.md`
- `docs/evidence/*`
- `README.md`
