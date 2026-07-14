# Backend Modernization Baseline

이 디렉터리는 Terraformers 후속 고도화 작업 중 **백엔드 개발과 운영환경 정리**에 해당하는 공개 기준선입니다.

## 1. 목적

원본 팀 프로젝트의 전체 backend source를 무조건 공개 저장소에 복사하는 것이 아니라, 다음 항목을 공개 가능한 형태로 정리합니다.

- Spring Boot backend 실행 기준
- RDB/Flyway schema migration 기준
- S3/SQS/Cognito/Secrets Manager runtime config contract
- Docker image build 기준
- 배포 후 health/runtime config 점검 기준

## 2. 현재 포함된 항목

```text
backend/
  pom.xml
  Dockerfile
  src/main/java/com/terraformers/modernization/
  src/main/resources/application.yml
  src/main/resources/application-prod.yml
  src/main/resources/db/migration/
  src/test/java/
```

현재 단계는 **public-safe backend baseline**입니다. 원본 Terraformers의 모든 API 구현을 옮긴 상태가 아니라, 후속 고도화 저장소에서 Maven/Docker/Flyway/runtime config 검증을 시작하기 위한 기준선입니다.

## 3. Local verification

```bash
cd backend
mvn -q test
mvn -q -DskipTests package
docker build -t terraformers-backend:local .
```

## 4. Runtime config contract

`prod` profile은 다음 값을 환경 변수 또는 Kubernetes Secret/ExternalSecret 경로로 주입받는 것을 전제로 합니다.

- `SPRING_DATASOURCE_URL`
- `SPRING_DATASOURCE_USERNAME`
- `SPRING_DATASOURCE_PASSWORD`
- `COGNITO_REGION`
- `COGNITO_USER_POOL_ID`
- `COGNITO_USER_POOL_CLIENT_ID`
- `COGNITO_JWKS_URL`
- `S3_BUCKET_NAME`
- `AI_LOG_QUEUE_URL`
- `TERRAFORM_LOG_QUEUE_URL`

검증 시에는 secret value를 출력하지 않고 key 존재 여부만 확인합니다.

## 5. Runtime check endpoint

```text
GET /actuator/health
GET /internal/runtime/required-config
```

`/internal/runtime/required-config`는 운영 노출용 public API가 아니라, 배포 후 runtime key 존재 여부를 점검하기 위한 내부 점검 surface입니다. 실제 배포에서는 ingress/security policy로 외부 노출을 제한해야 합니다.
