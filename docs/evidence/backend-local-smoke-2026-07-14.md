# Backend Local Smoke Evidence - 2026-07-14

## 1. Scope

This evidence records the local/stub backend smoke validation result reported from the WSL development environment.

This is not AWS production adapter evidence. It verifies that the Spring Boot backend can run locally with:

- default `local` profile;
- H2 in-memory database;
- JPA local schema generation;
- Flyway disabled;
- stub S3 reader/writer;
- stub reference retriever;
- stub analysis provider;
- logging progress publisher.

## 2. Command

Backend was started separately with:

```bash
cd backend
mvn spring-boot:run
```

Smoke script was executed from the repository root:

```bash
BASE_URL=http://localhost:8080 \
PROJECT_ID=project-smoke \
SOURCE_BUCKET=example-bucket \
SOURCE_KEY=uploads/architecture-diagram.png \
bash scripts/smoke/create-analysis-job.sh
```

## 3. Observed result

The smoke script created and fetched an analysis job successfully.

Sanitized observed values:

```text
status=SUCCEEDED
provider=stub-integrated-java
resultObjectKey=analysis-results/project-smoke/2026/07/14/<job-id>/main.tf
resultPreview=<non-empty Terraform draft>
failureReason=null
```

The script completed with:

```text
analysis job smoke assertions passed
status=SUCCEEDED
provider=stub-integrated-java
resultObjectKey=analysis-results/project-smoke/2026/07/14/<job-id>/main.tf
```

## 4. Meaning

This proves the local/stub baseline can complete the backend-owned analysis job lifecycle:

```text
POST /api/analysis/jobs
  -> persist analysis job
  -> run integrated Java stub provider
  -> store result object key through stub writer
  -> update job status to SUCCEEDED
  -> GET /api/analysis/jobs/{id}
```

## 5. Limitations

This evidence does not prove:

- real S3 object read/write;
- Bedrock generation;
- Bedrock embedding;
- OpenSearch/AOSS retrieval;
- SQS progress publishing;
- MariaDB/RDS Flyway migration;
- Kubernetes rollout;
- frontend browser flow.

Those should be validated in later stages by enabling one adapter boundary at a time.
