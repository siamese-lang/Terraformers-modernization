# Deployment

## 1. 목적

이 문서는 Terraformers 운영환경 고도화 프로젝트의 배포 흐름을 정리한다.

목표는 다음이다.

- Docker image build와 ECR publish 흐름을 명확히 한다.
- Terraform 기반 AWS infrastructure 변경과 애플리케이션 배포를 분리한다.
- GitHub Actions 검증 단계와 승인 기반 운영 단계를 구분한다.
- runtime config와 Secret 주입 방식을 문서화한다.
- 배포 후 검증해야 할 상태를 명확히 한다.

## 2. 배포 대상 구성요소

배포 대상은 다음으로 나눈다.

| 영역 | 대상 | 배포 방식 |
|---|---|---|
| Frontend | React SPA | build 후 S3 sync, CloudFront invalidation |
| Backend | Spring Boot API | Docker build, ECR push, Kubernetes Deployment rollout |
| Analysis Service | Python Bedrock service | Docker build, ECR push, Kubernetes Deployment rollout |
| Infrastructure | VPC, EKS, RDS, S3, SQS, IAM, CloudFront 등 | Terraform plan/apply |
| Runtime Config | DB, Cognito, S3, SQS, Bedrock/OpenSearch 설정 | 환경별 Secret provider / Kubernetes Secret |

## 3. 전체 배포 흐름

```text
Developer branch
  -> Pull Request
  -> GitHub Actions validation
  -> Merge to main
  -> Terraform plan/apply with approval
  -> ECR repository and AWS resources available
  -> Backend image build/publish
  -> Bedrock image build/publish
  -> Kubernetes manifest image tag update
  -> ArgoCD sync
  -> Kubernetes rollout status check
  -> Runtime Secret check
  -> API smoke and E2E validation
```

## 4. GitHub Actions 단계 구분

### 4.1 PR 검증 단계

PR 단계에서는 실제 인프라 변경이나 운영 배포를 바로 수행하지 않는다.

검증 항목은 다음이다.

- backend Maven compile/test
- backend Docker image build 가능 여부
- frontend build 가능 여부
- Terraform fmt/validate
- DynamoDB 등 legacy dependency 재도입 방지 guard
- production code에 secret value가 하드코딩되지 않았는지 점검
- Spring/Kubernetes/frontend 환경 계약 정합성

### 4.2 승인 기반 운영 단계

운영 반영 단계는 수동 실행과 명시적 승인을 기준으로 한다.

- Terraform apply는 `workflow_dispatch`로 실행한다.
- GitHub Environment approval을 사용한다.
- `confirm_apply=APPLY` 같은 명시적 입력을 요구한다.
- plan 상세 내용과 secret value를 CI log에 직접 노출하지 않는다.
- image publish는 ECR push 후 manifest image tag update commit으로 추적한다.

## 5. Terraform Infrastructure

Terraform은 다음 AWS 리소스를 관리하는 기준으로 둔다.

- VPC / subnet / security group
- EKS cluster / node group
- ECR repositories
- RDS MariaDB
- S3 buckets
- SQS queues
- Cognito
- IAM roles and policies
- Secrets Manager
- CloudFront / frontend hosting
- ArgoCD / Kubernetes bootstrap integration

운영 원칙은 다음이다.

- `terraform fmt`와 `terraform validate`를 먼저 통과해야 한다.
- plan과 apply는 분리한다.
- apply는 수동 승인 기반으로만 수행한다.
- remote state backend를 사용한다.
- DB, token, secret, account-specific 민감값은 repository에 기록하지 않는다.
- destroy는 일반 smoke 대상이 아니며, 비용 정리나 환경 종료 시 별도 승인 절차로만 수행한다.

## 6. Backend Image Build / Publish

Backend image는 Spring Boot 애플리케이션을 container runtime에서 실행하기 위한 산출물이다.

권장 흐름은 다음이다.

```text
backend source change
  -> Maven compile/test
  -> Docker build
  -> ECR login
  -> ECR push
  -> Kubernetes backend deployment manifest image tag update
  -> manifest update commit
  -> ArgoCD sync
  -> rollout status check
```

검증 기준은 다음이다.

- Maven compile/test가 통과해야 한다.
- Docker build가 성공해야 한다.
- image tag에 whitespace나 잘못된 값이 없어야 한다.
- ECR repository가 실제로 존재해야 한다.
- Kubernetes manifest의 image URI가 새 ECR image URI로 갱신되어야 한다.
- runtime deployment image와 Git manifest image가 일치해야 한다.
- `/actuator/health`가 200을 반환해야 한다.

## 7. Python Analysis Service Image Build / Publish

Python analysis service는 Bedrock/OpenSearch/SQS 연동을 수행하는 별도 runtime이다.

권장 흐름은 다음이다.

```text
python analysis source change
  -> Docker build
  -> ECR login
  -> ECR push
  -> Kubernetes bedrock deployment manifest image tag update
  -> manifest update commit
  -> ArgoCD sync
  -> rollout status check
  -> /health and log check
```

검증 기준은 다음이다.

- Docker build가 성공해야 한다.
- requirements dependency 설치가 실패하지 않아야 한다.
- ECR repository가 실제로 존재해야 한다.
- manifest image tag가 최신 image와 일치해야 한다.
- pod가 `Running` 상태여야 한다.
- `/health` endpoint가 정상 응답해야 한다.
- Bedrock model ID, OpenSearch endpoint, vector field, content field runtime config가 누락되지 않아야 한다.
- SQS publish 오류가 없어야 한다.

## 8. Frontend Build / Deploy

Frontend는 React SPA build 결과를 S3에 배포하고 CloudFront로 제공한다.

권장 흐름은 다음이다.

```text
frontend source change
  -> npm ci/build
  -> S3 sync
  -> CloudFront invalidation
  -> browser smoke test
```

Frontend production build에는 공개 가능한 다음 값만 전달한다.

- `REACT_APP_API_BASE_URL`
- `REACT_APP_AWS_REGION`
- `REACT_APP_COGNITO_USER_POOL_ID`
- `REACT_APP_COGNITO_USER_POOL_CLIENT_ID`

DB credential, queue URL, model ID, OpenSearch 설정, S3 object identifier 같은 server-side 값은 frontend build contract에 포함하지 않는다.

주의할 점은 frontend 개발 자체를 본인 핵심 기여로 설명하지 않는다는 것이다. 이 프로젝트에서는 frontend를 사용자의 E2E 흐름을 검증하기 위한 client surface로 설명한다.

## 9. Runtime Config / Secret Injection

정확한 key와 미확정 AWS 연결 상태는 [`aws-environment-contract.md`](aws-environment-contract.md)를 canonical 기준으로 사용한다.

환경별 권장 흐름은 다음과 같다.

```text
Terraform outputs / AWS managed configuration
  -> approved GitHub Environment or Secret provider
  -> terraformers-backend-runtime-secrets
  -> backend container env
```

특정 Secret provider는 아직 고정하지 않는다. External Secrets, Sealed Secrets, 승인된 CI/CD injection 등 환경별 방식을 선택할 수 있지만, repository에는 실제 Secret resource나 값이 포함되면 안 된다.

### 9.1 Backend base production contract

다음 8개 key는 `application-prod.yml`의 필수 계약이다.

- `SPRING_DATASOURCE_URL`
- `SPRING_DATASOURCE_USERNAME`
- `SPRING_DATASOURCE_PASSWORD`
- `COGNITO_REGION`
- `COGNITO_USER_POOL_ID`
- `COGNITO_USER_POOL_CLIENT_ID`
- `COGNITO_JWKS_URL`
- `S3_BUCKET_NAME`

`ANALYSIS_RESULT_BUCKET_NAME`은 선택적 override다. 누락되면 `S3_BUCKET_NAME`을 결과 bucket으로 사용한다.

다음 과거 문서 alias는 canonical backend contract가 아니다.

- `AWS_S3_BUCKET_NAME`
- `FRONTEND_URL`
- `DOMAIN`

### 9.2 Optional adapter contract

Adapter는 base와 AWS public template에서 기본적으로 비활성화한다.

- `BEDROCK_PROVIDER_ENABLED=true` → `BEDROCK_MODEL_ID`
- `BEDROCK_EMBEDDING_ENABLED=true` → `BEDROCK_EMBEDDING_MODEL_ID`
- `OPENSEARCH_RETRIEVER_ENABLED=true` → `OPENSEARCH_ENDPOINT`, `INDEX_NAME`, `VECTOR_FIELD_NAME`, `CONTENT_FIELD_NAME`
- `ANALYSIS_SQS_PUBLISHER_ENABLED=true` → `AI_LOG_QUEUE_URL`, `TERRAFORM_LOG_QUEUE_URL`
- `S3_READER_ENABLED=true` / `S3_WRITER_ENABLED=true` → bucket 설정과 workload IAM 권한 확인

Adapter switch는 AWS resource, network path, IAM policy, runtime key를 함께 검증한 뒤 하나씩 활성화한다.

### 9.3 Non-secret ConfigMap contract

`terraformers-backend-runtime-config`는 다음과 같은 비밀이 아닌 runtime state를 전달한다.

- `SPRING_PROFILES_ACTIVE=prod`
- adapter enable/disable switch
- Bedrock token limit
- OpenSearch service name/top-k
- result object key prefix
- 환경별 AWS region

운영 점검 원칙은 다음이다.

- secret value를 출력하지 않는다.
- key 존재 여부만 확인한다.
- target Secret 생성 여부와 Deployment의 `secretRef` 이름을 비교한다.
- pod startup error가 있으면 누락된 base key 또는 활성 adapter key와 연결해 진단한다.
- ServiceAccount IRSA annotation과 workload IAM policy를 별도로 검증한다.

## 10. 배포 순서

최소 권장 배포 순서는 다음이다.

1. static AWS environment contract 검증
2. Terraform output과 GitHub repository/environment variable·secret mapping 확정
3. GitHub Environment approval rule 설정
4. Terraform backend/bootstrap 준비
5. Terraform fmt/validate/plan 확인
6. Terraform apply 실행
7. ECR repository, RDS, S3, SQS, Cognito output 확인
8. runtime Secret provider와 ServiceAccount IRSA 확인
9. backend image build/publish
10. Python analysis service image build/publish
11. frontend build/deploy
12. ArgoCD sync 확인
13. Kubernetes rollout status 확인
14. runtime Secret 상태 확인
15. backend health check
16. analysis service health check
17. API smoke test
18. browser E2E test
19. log inspection

## 11. 배포 완료 판단 기준

배포 완료는 단순히 workflow가 성공했다는 의미가 아니다.

다음이 함께 확인되어야 한다.

- Terraform apply가 성공했고 필요한 output이 확인된다.
- Terraform output, GitHub configuration, Kubernetes env, application property mapping이 일치한다.
- ECR에 backend/analysis service image가 push되었다.
- Kubernetes manifest image tag가 해당 image URI로 갱신되었다.
- ArgoCD sync 결과가 정상이다.
- deployment rollout이 성공했다.
- service endpoint가 존재한다.
- runtime Secret contract와 ServiceAccount IAM contract가 충족된다.
- backend `/actuator/health`가 정상이다.
- analysis service `/health`가 정상이다.
- 업로드 → 분석 → SQS log/result → 결과 조회 흐름이 동작한다.

## 12. 운영상 주의사항

- 실제 token, password, account id, secret value는 문서·로그·커밋에 남기지 않는다.
- Terraform plan 상세와 secret이 CI log에 노출되지 않도록 한다.
- source merge, image publish, manifest update, runtime rollout은 서로 다른 단계임을 구분한다.
- 배포 후에는 반드시 image tag consistency를 확인한다.
- RDS schema 변경은 임의 DDL이 아니라 Flyway migration으로 관리한다.
- destroy는 비용 정리 목적 외에는 기본 운영 절차로 다루지 않는다.
