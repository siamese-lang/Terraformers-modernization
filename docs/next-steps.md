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

## 2. Adapter validation

Validate one production adapter at a time instead of enabling every runtime dependency at once.

Recommended order:

1. `S3_READER_ENABLED=true`
2. `S3_WRITER_ENABLED=true`
3. `BEDROCK_PROVIDER_ENABLED=true`
4. `BEDROCK_EMBEDDING_ENABLED=true`
5. `OPENSEARCH_RETRIEVER_ENABLED=true`
6. `ANALYSIS_SQS_PUBLISHER_ENABLED=true`

Use [`docs/runbooks/backend-analysis-adapter-failures.md`](runbooks/backend-analysis-adapter-failures.md) to isolate failures by adapter boundary.

## 3. Infrastructure import

After backend baseline verification, import Terraform in this order:

1. `infra/terraform/envs/dev`
2. network/security group modules
3. ECR/RDS/S3/SQS/Secrets Manager/Cognito modules
4. Kubernetes backend manifests
5. image publish workflows
6. Terraform plan/apply workflows

Do not import the full private repository history.

## 4. Runtime deployment variables

The next implementation step is to wire the new adapter switches into Terraform/Kubernetes manifests:

- `S3_READER_ENABLED`
- `S3_WRITER_ENABLED`
- `ANALYSIS_RESULT_BUCKET_NAME`
- `ANALYSIS_RESULT_KEY_PREFIX`
- `BEDROCK_PROVIDER_ENABLED`
- `BEDROCK_EMBEDDING_ENABLED`
- `OPENSEARCH_RETRIEVER_ENABLED`
- `OPENSEARCH_SERVICE_NAME`
- `OPENSEARCH_TOP_K`
- `ANALYSIS_SQS_PUBLISHER_ENABLED`

## 5. Documentation updates

After each infrastructure/runtime change, update:

- `docs/validation.md`
- `docs/runbook.md`
- `docs/runbooks/*`
- `docs/evidence/*`
- `README.md`
