# Validation

## 1. Purpose

This document defines validation steps for the Terraformers backend and cloud infrastructure modernization baseline.

Validation focuses on proving that a code or workflow success is actually reflected in runtime behavior.

Key goals:

- distinguish source merge, image build, deployment manifest update, and runtime rollout;
- verify Spring Boot backend startup, DB schema compatibility, and runtime config injection;
- validate the backend-owned analysis job lifecycle;
- isolate failures across S3 source read, reference retrieval, Bedrock generation, S3 result write, and SQS progress publishing;
- avoid exposing secret values in logs or evidence.

## 2. Validation principles

- Do not print secret values.
- Do not commit real tokens, passwords, account IDs, ARNs, queue URLs, kubeconfig, tfstate, or tfvars.
- Do not claim deployment success from GitHub Actions alone.
- Validate runtime image tag, pod rollout, health endpoint, and API smoke behavior.
- Use stub adapters for local/CI validation.
- Enable AWS adapters one by one in deployment validation.

## 3. Current GitHub Actions policy

During the public baseline construction phase, verification workflows are intentionally manual-only.

```text
on: workflow_dispatch
```

Manual-only workflows:

- Backend Maven Verification
- Backend Image Build Verification
- Runtime Contract Verification

This is intentional. The repository is still stabilizing backend adapter code and deployment contract skeletons. Automatic push/PR checks should be re-enabled only after local verification and manual workflow runs pass reliably.

## 4. Pre-deploy validation

### 4.1 Backend Maven and tests

Run:

```bash
cd backend
mvn test
mvn -DskipTests package
```

Expected:

- compilation succeeds;
- local Spring context loads with H2 and stub adapters;
- analysis job API integration test returns `SUCCEEDED`, `resultObjectKey`, and `resultPreview`;
- unit tests for runtime config, object storage, analysis orchestration, and OpenSearch query parsing pass;
- no AWS credentials are required for default tests.

Local runtime details are documented in [`docs/backend-local-runtime.md`](backend-local-runtime.md).

### 4.2 Backend image build

Run:

```bash
cd backend
docker build -t terraformers-backend:local .
```

Expected:

- image builds without embedding secrets;
- image contains the Spring Boot artifact;
- healthcheck path matches `/actuator/health`.

### 4.3 Runtime contract verification

Preferred command:

```bash
bash scripts/checks/runtime-contract-verification.sh
```

The script verifies:

- `kubectl kustomize infra/kubernetes/base` renders ConfigMap, ServiceAccount, Deployment, and Service;
- `backend-secret.example.yaml` is not rendered by the public base kustomization;
- ServiceAccount does not contain a public committed IAM role ARN;
- rendered base does not contain 12-digit account-like identifiers or `replace-me` placeholders;
- committed example files use placeholder-only values;
- Terraform runtime contract passes `terraform fmt -check`, `terraform validate`, and `terraform plan -var-file=terraform.tfvars.example`.

Equivalent manual commands:

```bash
kubectl kustomize infra/kubernetes/base

cd infra/terraform/runtime-contract
terraform init -backend=false -input=false
terraform fmt -check
terraform validate
terraform plan -input=false -lock=false -var-file=terraform.tfvars.example
```

Expected:

- Kubernetes manifests render;
- Terraform variable contract validates;
- example values remain placeholders only;
- no real account ID, ARN, queue URL, bucket name, password, token, kubeconfig, tfstate, or `.tfvars` content appears in output or evidence.

## 5. Local/stub runtime validation

Local and CI validation should run with AWS adapters disabled.

```text
S3_READER_ENABLED=false
S3_WRITER_ENABLED=false
BEDROCK_PROVIDER_ENABLED=false
BEDROCK_EMBEDDING_ENABLED=false
OPENSEARCH_RETRIEVER_ENABLED=false
ANALYSIS_SQS_PUBLISHER_ENABLED=false
```

This path uses:

```text
H2 in-memory database
JPA schema generation
Flyway disabled
StubObjectReader
StubObjectWriter
StubEmbeddingProvider
StubReferenceRetriever
StubAnalysisProvider
LoggingProgressPublisher
```

Run the backend and execute:

```bash
BASE_URL=http://localhost:8080 \
PROJECT_ID=project-smoke \
SOURCE_BUCKET=example-bucket \
SOURCE_KEY=uploads/architecture-diagram.png \
bash scripts/smoke/create-analysis-job.sh
```

Expected:

```text
analysis job smoke assertions passed
status=SUCCEEDED
provider=stub-integrated-java
resultObjectKey=analysis-results/...
```

## 6. Production adapter validation order

Enable one adapter class of dependency at a time.

Recommended order:

1. `S3_READER_ENABLED=true`
2. `S3_WRITER_ENABLED=true`
3. `BEDROCK_PROVIDER_ENABLED=true`
4. `BEDROCK_EMBEDDING_ENABLED=true`
5. `OPENSEARCH_RETRIEVER_ENABLED=true`
6. `ANALYSIS_SQS_PUBLISHER_ENABLED=true`

Do not enable every adapter at once on the first deployment. If several adapters are enabled together, the failure domain becomes harder to isolate.

## 7. Post-deploy Kubernetes validation

Check runtime resources:

```bash
kubectl get deploy,po,svc,endpoints
kubectl rollout status deployment/terraformers-backend
kubectl logs deployment/terraformers-backend --tail=200
```

Expected:

- deployment available;
- pod `Running`;
- service endpoint exists;
- restart count is not continuously increasing;
- backend log does not show DB, secret, schema, S3, Bedrock, OpenSearch, or SQS startup errors.

## 8. Image tag consistency

Runtime deployment must use the intended immutable image tag.

```bash
kubectl get deploy terraformers-backend -o jsonpath='{.spec.template.spec.containers[*].image}'
```

Expected:

- image URI matches the Git manifest or environment overlay;
- placeholder image is removed in environment-specific overlays;
- `latest` is not used for evidence-grade validation.

## 9. Runtime config and secret validation

Check key presence, not values.

```bash
kubectl get configmap terraformers-backend-runtime-config
kubectl get secret terraformers-backend-runtime-secrets
kubectl describe deploy terraformers-backend
```

Expected:

- ConfigMap contains adapter switches;
- Secret contains datasource, Cognito, S3, SQS, Bedrock, and OpenSearch runtime keys;
- deployment uses both ConfigMap and Secret through `envFrom`;
- no real secret value is pasted into documentation or evidence.

## 10. Backend health validation

Run:

```bash
curl -i http://<backend-url>/actuator/health
```

Expected:

- HTTP 200;
- JSON response;
- no datasource connection failure;
- no Flyway validation error;
- no Hibernate schema validation error.

## 11. Analysis job API smoke validation

Run:

```bash
BASE_URL=http://<backend-url> \
PROJECT_ID=<project-id> \
SOURCE_BUCKET=<upload-bucket> \
SOURCE_KEY=<uploaded-image-key> \
bash scripts/smoke/create-analysis-job.sh
```

Expected success response:

```text
status=SUCCEEDED
provider=<stub-integrated-java or bedrock-integrated-java>
resultObjectKey=<non-empty object key>
resultPreview=<non-empty preview>
failureReason=null
```

If the job fails, inspect `failureReason` first and then use [`docs/runbooks/backend-analysis-adapter-failures.md`](runbooks/backend-analysis-adapter-failures.md).

## 12. Adapter-specific checks

### 12.1 S3 source read

Expected:

- source object exists;
- object content type is image-supported;
- runtime role has `s3:HeadObject` and `s3:GetObject`.

### 12.2 S3 result write

Expected:

- result bucket exists;
- result prefix is allowed;
- runtime role has `s3:PutObject`;
- `analysis_jobs.result_object_key` is populated after success.

### 12.3 Bedrock generation

Expected:

- model ID is valid in the deployment region;
- runtime role can invoke the configured model;
- prompt builder accepts source object media type;
- response parser extracts Terraform HCL text.

### 12.4 Bedrock embedding and OpenSearch retrieval

Expected:

- embedding model returns vector with expected dimension;
- OpenSearch/AOSS endpoint is normalized correctly;
- SigV4 service name is `aoss` for OpenSearch Serverless or `es` for classic domain when applicable;
- index mapping matches `VECTOR_FIELD_NAME` and `CONTENT_FIELD_NAME`.

### 12.5 SQS progress publishing

Expected:

- queue URLs match environment;
- runtime role has `sqs:SendMessage`;
- frontend/backend polling uses the same job/project correlation;
- RDB job state remains the source of truth even if SQS progress is delayed.

## 13. DB migration and schema validation

Check startup logs and, if needed, database migration history.

```sql
SELECT installed_rank, version, description, script, success
FROM flyway_schema_history
ORDER BY installed_rank;
```

Expected:

- Flyway migrations are successful;
- `analysis_jobs` exists;
- `provider`, `result_object_key`, and `result_preview` columns exist;
- Hibernate validate passes.

## 14. Evidence to keep

For portfolio or interview evidence, keep sanitized proof of:

- manual GitHub Actions backend Maven verification after baseline stabilization;
- backend image build;
- Kubernetes rendered manifest or environment overlay;
- runtime config key presence without secret values;
- backend rollout status;
- backend health response;
- analysis job smoke success with `SUCCEEDED`, `resultObjectKey`, and `resultPreview`;
- adapter failure runbook application if an intentional failure test is performed.

## 15. Interview explanation

```text
검증은 workflow 성공에서 끝내지 않고, 실제 runtime에서 backend image가 반영됐는지, ConfigMap/Secret 계약이 맞는지, health check와 analysis job smoke가 통과하는지까지 확인하도록 구성했습니다. 로컬 검증은 H2와 stub adapter로 API/RDB/job lifecycle을 먼저 고정하고, production 검증은 MariaDB/Flyway와 AWS adapter를 순차적으로 켜는 방식으로 분리했습니다. 현재는 baseline 구축 단계이므로 GitHub Actions는 수동 검증으로 두고, 로컬 검증과 수동 workflow가 안정화된 뒤 push/PR 자동 검증을 다시 켜는 방향으로 정리했습니다.
```
