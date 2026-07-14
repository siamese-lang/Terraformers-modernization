# Backend Public Baseline

## 1. 목적

이 문서는 `backend/` 디렉터리에 추가된 공개 backend 기준선의 의미와 한계를 정리한다.

현재 backend 코드는 원본 Terraformers 전체 backend source를 그대로 공개 저장소에 복사한 것이 아니다. 공개 저장소에서 먼저 검증 가능한 형태로 유지해야 하는 항목을 분리한 **public-safe backend modernization baseline**이다.

## 2. 현재 포함 범위

포함된 항목:

- Maven 기반 Spring Boot 3.3 / Java 17 프로젝트 구조
- backend Dockerfile
- actuator health check
- runtime config key presence inspection endpoint
- prod profile datasource/Flyway/JPA validate contract
- Flyway baseline schema
- runtime config inspector unit test
- Maven verification workflow
- Docker image build workflow

## 3. 아직 포함하지 않은 항목

아직 포함하지 않은 항목:

- 원본 Terraformers 전체 controller/service/repository 구현
- 실제 Cognito token validation implementation
- 실제 S3 upload implementation
- 실제 SQS polling implementation
- 실제 Bedrock service client 호출 implementation
- 실제 프로젝트/파일/댓글 API 전체 구현
- Terraform apply/run API implementation

이 항목들은 다음 단계에서 공개 가능 여부와 secret/account-specific 정보 포함 여부를 점검한 뒤 선별 이전한다.

## 4. 검증 명령

```bash
bash scripts/checks/backend-local-verification.sh
```

또는 직접 실행한다.

```bash
cd backend
mvn -q test
mvn -q -DskipTests package
docker build -t terraformers-backend:local .
```

## 5. 공개 저장소 기준 완료 조건

이 기준선의 목적은 다음 조건을 만족하는 것이다.

```text
backend source가 존재한다 -> Maven test/package가 가능하다 -> Docker image를 만들 수 있다 -> prod runtime config contract가 분리되어 있다 -> Flyway schema 기준이 있다 -> GitHub Actions로 반복 검증할 수 있다.
```

## 6. 다음 이전 대상

다음 단계에서는 아래 항목을 private 작업물에서 선별한다.

1. 실제 domain entity/repository/service 중 공개 가능한 코드
2. Cognito user mapping 흐름
3. S3 object storage adapter
4. SQS log polling adapter
5. project/file/comment API 중 본인 후속 고도화 범위와 맞는 코드
6. backend smoke script

선별 기준은 `docs/migration-plan.md`를 따른다.
