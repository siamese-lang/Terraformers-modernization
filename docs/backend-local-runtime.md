# Backend Local Runtime Baseline

## 1. Purpose

The local backend runtime exists to prove that the Spring Boot API, RDB-backed job lifecycle, stub adapters, and smoke tests can run before AWS deployment work starts.

Local runtime is not a production-equivalent database or cloud adapter environment.

## 2. Local profile

The default Spring profile is `local`.

```text
SPRING_PROFILES_ACTIVE=local
```

The local profile uses:

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

This allows `POST /api/analysis/jobs` and `GET /api/analysis/jobs/{id}` to run without AWS credentials.

## 3. Why Flyway is disabled locally

Production uses MariaDB-compatible Flyway migrations and Hibernate validation.

Local smoke testing uses H2 only to verify controller, service, repository, entity, and adapter wiring. MariaDB-specific migration syntax is validated in the production runtime path, not in the local stub path.

This avoids turning local smoke into a false production simulation.

## 4. Local validation flow

Run backend tests:

```bash
cd backend
mvn test
```

Run the backend locally:

```bash
cd backend
mvn spring-boot:run
```

Run the smoke script:

```bash
BASE_URL=http://localhost:8080 \
PROJECT_ID=project-smoke \
SOURCE_BUCKET=example-bucket \
SOURCE_KEY=uploads/architecture-diagram.png \
bash scripts/smoke/create-analysis-job.sh
```

Expected result:

```text
status=SUCCEEDED
provider=stub-integrated-java
resultObjectKey=analysis-results/...
resultPreview=<non-empty>
```

## 5. Production profile contrast

Production profile uses:

```text
SPRING_PROFILES_ACTIVE=prod
MariaDB/RDS datasource
Flyway enabled
Hibernate ddl-auto=validate
AWS adapters enabled only through feature flags
```

Production adapter validation should enable one dependency boundary at a time:

```text
S3_READER_ENABLED
S3_WRITER_ENABLED
BEDROCK_PROVIDER_ENABLED
BEDROCK_EMBEDDING_ENABLED
OPENSEARCH_RETRIEVER_ENABLED
ANALYSIS_SQS_PUBLISHER_ENABLED
```

## 6. Portfolio explanation

```text
로컬 검증은 운영환경을 흉내 내기 위한 것이 아니라, Spring Boot backend의 API, JPA repository, analysis job lifecycle, stub adapter 연결이 깨지지 않았는지 확인하기 위한 기준으로 구성했습니다. 운영 검증은 별도로 MariaDB/Flyway와 AWS adapter를 켜서 수행하도록 분리했습니다.
```
