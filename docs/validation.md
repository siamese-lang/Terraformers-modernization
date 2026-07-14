# Validation

## 1. 목적

이 문서는 Terraformers 운영환경 고도화 프로젝트의 배포 후 검증 절차를 정리한다.

검증의 목적은 다음이다.

- workflow 성공과 실제 runtime 반영을 구분한다.
- 배포된 image tag가 manifest와 일치하는지 확인한다.
- DB schema와 application entity 정합성을 확인한다.
- S3/SQS/RDS/Secret 등 외부 의존성 연동을 확인한다.
- 사용자의 주요 E2E 흐름이 정상 동작하는지 확인한다.
- 장애 발생 시 어느 계층부터 확인할지 근거를 남긴다.

## 2. 검증 원칙

- secret value는 출력하지 않는다.
- token, password, account id, ARN, queue URL 등 민감하거나 계정 특정적인 값은 문서에 그대로 남기지 않는다.
- 단순히 `workflow success`만으로 배포 완료를 주장하지 않는다.
- source merge, image build, image push, manifest update, ArgoCD sync, pod rollout을 구분한다.
- 오류가 발생하면 frontend/backend/analysis service/RDB/S3/SQS/Secret/CloudFront 계층별로 분리해 확인한다.

## 3. Pre-deploy Validation

### 3.1 Backend

확인 항목은 다음이다.

- Maven compile 성공
- focused test 성공
- full test 성공
- production code에 legacy DynamoDB dependency가 재도입되지 않았는지 확인
- production datasource가 env/secret contract를 따르는지 확인
- Flyway migration 파일이 존재하는지 확인
- Docker image build 성공

### 3.2 Python Analysis Service

확인 항목은 다음이다.

- Docker image build 성공
- requirements 설치 성공
- `/health` endpoint 존재
- runtime env 누락 시 명확한 실패 또는 로그가 남는지 확인
- Bedrock/OpenSearch/SQS 설정이 코드에 하드코딩되지 않았는지 확인

### 3.3 Terraform

확인 항목은 다음이다.

- `terraform fmt -check`
- `terraform validate`
- manual plan 성공
- plan 상세와 secret value가 CI log에 노출되지 않는지 확인
- ECR, RDS, S3, SQS, Cognito, Secrets Manager 관련 output이 필요한 수준으로 정의되어 있는지 확인

### 3.4 Frontend

확인 항목은 다음이다.

- npm install/build 성공
- API base URL과 Cognito config가 runtime 또는 build-time variable과 일치하는지 확인
- frontend는 같은 domain의 `/api/*` 경로 또는 명확한 backend endpoint를 사용한다.

## 4. Post-deploy Runtime Validation

### 4.1 Kubernetes / Container Runtime

확인 항목은 다음이다.

```bash
kubectl get deploy,po,svc -n default
kubectl rollout status deployment/backend-app -n default
kubectl rollout status deployment/bedrock-service -n default
kubectl get endpoints -n default
```

정상 기준은 다음이다.

- backend deployment available
- bedrock deployment available
- pod `Running`
- service endpoint 존재
- restart count가 지속적으로 증가하지 않음

### 4.2 Image Tag Consistency

확인 목적은 “코드가 merge된 상태”와 “실제 runtime에 반영된 image”를 구분하는 것이다.

확인 항목은 다음이다.

```bash
kubectl get deploy backend-app -n default -o jsonpath='{.spec.template.spec.containers[*].image}'
kubectl get deploy bedrock-service -n default -o jsonpath='{.spec.template.spec.containers[*].image}'
```

정상 기준은 다음이다.

- backend deployment image가 Git manifest의 backend image URI와 일치한다.
- bedrock deployment image가 Git manifest의 bedrock image URI와 일치한다.
- DockerHub placeholder image가 남아 있지 않다.
- latest tag에 의존하지 않고 commit SHA 또는 명시적 release tag를 사용한다.

### 4.3 External Secrets / Runtime Secret

확인 항목은 다음이다.

```bash
kubectl get crd | grep external-secrets
kubectl get pods -n external-secrets
kubectl get secretstore -n default
kubectl get externalsecret -n default
kubectl get secret -n default
```

정상 기준은 다음이다.

- External Secrets CRD 존재
- controller pod Running
- SecretStore Ready
- ExternalSecret Ready 또는 SecretSynced
- backend와 analysis service가 요구하는 target Secret 존재

주의할 점은 다음이다.

- secret value를 출력하지 않는다.
- 필요하면 `.data`의 key 목록만 확인한다.
- 누락된 key가 있을 경우 pod `CreateContainerConfigError` 또는 startup error와 연결해 진단한다.

### 4.4 Backend Health Check

확인 항목은 다음이다.

```bash
curl -i https://<service-domain>/actuator/health
```

정상 기준은 다음이다.

- HTTP 200
- JSON response
- DB connection 관련 error 없음
- `Schema-validation` error 없음
- `Failed to load driver class` error 없음

### 4.5 Analysis Service Health Check

확인 항목은 다음이다.

```bash
curl -i http://<bedrock-service>/health
kubectl logs deployment/bedrock-service -n default --tail=100
```

정상 기준은 다음이다.

- HTTP 200
- `status: healthy` 등 명확한 health response
- Bedrock/OpenSearch/SQS config 누락 오류 없음
- endpoint parse error 없음
- AccessDenied 오류 없음

## 5. API Smoke Test

기본 smoke 순서는 다음이다.

| 순서 | 검증 항목 | 기대 결과 |
|---|---|---|
| 1 | `GET /actuator/health` | 200 |
| 2 | `GET /api/public-projects` | 200 JSON |
| 3 | 인증 없는 보호 API 호출 | 401 또는 403 |
| 4 | 인증 포함 프로젝트 API 호출 | 200 |
| 5 | 이미지 업로드 API 호출 | projectId / file metadata 생성 |
| 6 | AI/Terraform logs polling | 현재 projectId 기준 로그 조회 |
| 7 | project tree 조회 | 업로드 이미지와 생성 파일 node 확인 |
| 8 | visibility PUBLIC 전환 | 공개 목록 노출 |
| 9 | 댓글 작성/조회 | RDB comment 반영 |

## 6. E2E Validation Flow

브라우저 또는 API 기반 E2E flow는 다음 순서로 수행한다.

```text
1. 사용자 회원가입 또는 로그인
2. access token 확보
3. 이미지 업로드
4. backend가 RDB project/file metadata 생성
5. backend가 S3에 이미지 저장
6. backend가 Python analysis service 호출
7. Python analysis service가 Bedrock/OpenSearch 처리 수행
8. Python analysis service가 SQS에 로그와 결과 publish
9. frontend가 backend를 통해 logs/result polling
10. 생성된 Terraform code draft 표시
11. project detail 조회
12. project tree 조회
13. visibility PUBLIC 전환
14. public projects 목록 확인
15. comment 작성/조회
```

## 7. DB Migration / Schema Validation

검증 항목은 다음이다.

- Flyway migration table 존재
- migration success 상태 확인
- application startup 시 Hibernate validate 통과
- 누락 table 또는 column error 없음
- 임의 수동 DDL과 migration history 불일치 없음

예상 오류와 의미는 다음이다.

| 오류 | 의미 | 우선 확인 |
|---|---|---|
| `Schema-validation: missing table` | entity와 DB schema 불일치 | Flyway migration 누락 여부 |
| `Flyway validation failed` | migration history와 파일 불일치 또는 실패 이력 | `flyway_schema_history` |
| `Connections using insecure transport are prohibited` | RDS TLS 설정과 JDBC URL 불일치 | datasource SSL parameter |
| `Failed to load driver class org.mariadb.jdbc.Driver` | runtime dependency 누락 | backend image / pom dependency |
| `Connect timed out` | SG/network/RDS endpoint 문제 | RDS SG inbound, EKS source SG |

## 8. S3 / SQS Validation

### 8.1 S3

확인 항목은 다음이다.

- upload 후 S3 object 생성 여부
- RDB metadata의 object key와 실제 S3 key 일치 여부
- AccessDenied 발생 여부
- bucket name이 runtime config와 일치하는지 여부

### 8.2 SQS

확인 항목은 다음이다.

- queue URL이 runtime config와 일치하는지 여부
- Python analysis service가 progress log를 publish하는지 여부
- final terraform result message가 publish되는지 여부
- backend polling API가 현재 projectId 기준 메시지를 필터링하는지 여부
- queue mismatch 또는 stale queue URL 오류가 없는지 여부

## 9. Log Inspection Checklist

### 9.1 Backend logs

확인 대상은 다음이다.

- auth token validation failure
- SQL exception
- datasource connection error
- Flyway migration error
- S3 access error
- SQS queue mismatch
- project forbidden / not found
- CORS preflight error

### 9.2 Analysis service logs

확인 대상은 다음이다.

- incoming `/analyze` request
- S3 image read
- image media type detection
- Bedrock invocation
- OpenSearch search
- SQS publish
- AccessDenied
- endpoint parse error
- model ID mismatch

### 9.3 CloudFront / API routing

확인 대상은 다음이다.

- API 요청이 React `index.html`을 반환하지 않는지 확인
- `/api/*` behavior가 backend origin으로 전달되는지 확인
- OPTIONS preflight 응답이 JSON/API 계층에서 처리되는지 확인
- authorization header forwarding이 누락되지 않았는지 확인

## 10. Evidence로 남길 항목

포트폴리오 제출 또는 면접 준비 시 다음 증거를 준비한다.

- GitHub Actions workflow 목록
- backend Maven/test 성공 결과
- backend image build/publish 결과
- bedrock image build/publish 결과
- Terraform plan/apply approval 구조
- ECR image tag와 manifest image tag 비교
- Kubernetes rollout status
- ExternalSecret sync 상태
- backend health check 결과
- 이미지 업로드 후 S3/RDB/SQS 흐름 검증 결과
- 주요 장애 runbook 적용 사례
