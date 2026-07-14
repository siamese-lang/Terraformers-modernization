# Next Steps

## 1. Immediate validation

1. Check GitHub Actions results for:
   - Backend Maven Verification
   - Backend Image Build Verification
2. If either workflow fails, fix the public backend baseline before importing more code.
3. Run local verification if needed:

```bash
bash scripts/checks/backend-local-verification.sh
```

4. Run backend locally and execute the analysis job smoke script:

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
- `docs/deployment-runtime-contract.md`

Validate Kubernetes skeleton rendering:

```bash
kubectl kustomize infra/kubernetes/base
```

Validate Terraform runtime contract shape:

```bash
cd infra/terraform/runtime-contract
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars.example
```

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

After backend baseline verification, import Terraform in this order:

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
