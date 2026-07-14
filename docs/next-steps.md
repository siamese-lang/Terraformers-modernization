# Next Steps

## 1. Immediate validation

1. Check GitHub Actions results for:
   - Backend Maven Verification
   - Backend Image Build Verification
   - Runtime Contract Verification
2. If any workflow fails, fix the public baseline before importing more code.
3. Run local backend verification if needed:

```bash
bash scripts/checks/backend-local-verification.sh
```

4. Run runtime contract verification if Kubernetes or Terraform runtime files changed:

```bash
bash scripts/checks/runtime-contract-verification.sh
```

5. Run backend locally and execute the analysis job smoke script:

```bash
BASE_URL=http://localhost:8080 \
PROJECT_ID=project-smoke \
SOURCE_BUCKET=example-bucket \
SOURCE_KEY=uploads/architecture-diagram.png \
bash scripts/smoke/create-analysis-job.sh
```

The smoke script should confirm `SUCCEEDED`, `resultObjectKey`, and `resultPreview`.

## 2. Runtime contract validation

The runtime deployment contract now exists in:

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

## 3. Adapter validation

Validate one production adapter at a time instead of enabling every runtime dependency at once.

Recommended order:

1. `S3_READER_ENABLED=true`
2. `S3_WRITER_ENABLED=true`
3. `BEDROCK_PROVIDER_ENABLED=true`
4. `BEDROCK_EMBEDDING_ENABLED=true`
5. `OPENSEARCH_RETRIEVER_ENABLED=true`
6. `ANALYSIS_SQS_PUBLISHER_ENABLED=true`

Use [`docs/runbooks/backend-analysis-adapter-failures.md`](runbooks/backend-analysis-adapter-failures.md) to isolate failures by adapter boundary.

## 4. Infrastructure import

After backend and runtime contract verification, import Terraform in this order:

1. network/security group modules
2. ECR/RDS/S3/SQS/Secrets Manager/Cognito modules
3. IAM role and policy for backend runtime adapter access
4. External Secrets / SecretStore wiring
5. environment-specific Kubernetes overlays
6. image publish workflows
7. Terraform plan/apply workflows

Do not import the full private repository history.

## 5. Documentation updates

After each infrastructure/runtime change, update:

- `docs/validation.md`
- `docs/runbook.md`
- `docs/runbooks/*`
- `docs/evidence/*`
- `README.md`
