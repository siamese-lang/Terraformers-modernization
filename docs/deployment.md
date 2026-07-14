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
| Runtime Config | DB, Cognito, S3, SQS, Bedrock/OpenSearch 설정 | Secrets Manager / External Secrets / Kubernetes Secret |

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
  -> ExternalSecret / runtime Secret check
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
  -> npm install/build
  -> S3 sync
  -> CloudFront invalidation
  -> browser smoke test
```

주의할 점은 frontend 개발 자체를 본인 핵심 기여로 설명하지 않는다는 것이다. 이 프로젝트에서는 frontend를 사용자의 E2E 흐름을 검증하기 위한 client surface로 설명한다.

## 9. Runtime Config / Secret Injection

권장 runtime config 흐름은 다음이다.

```text
Terraform outputs / AWS managed secret
  -> Secrets Manager
  -> External Secrets Operator
  -> Kubernetes Secret
  -> backend / analysis service env
```

관리 대상은 다음이다.

### Backend runtime config

- `COGNITO_REGION`
- `COGNITO_USER_POOL_ID`
- `COGNITO_USER_POOL_CLIENT_ID`
- `COGNITO_JWKS_URL`
- `S3_BUCKET_NAME`
- `AWS_S3_BUCKET_NAME`
- `AWS_REGION`
- `FRONTEND_URL`
- `DOMAIN`

### Backend RDS config

- `SPRING_DATASOURCE_URL`
- `SPRING_DATASOURCE_USERNAME`
- `SPRING_DATASOURCE_PASSWORD`

### Analysis service config

- `BEDROCK_MODEL_ID`
- `BEDROCK_EMBEDDING_MODEL_ID`
- `AWS_OPENSEARCH_ENDPOINT`
- `VECTOR_FIELD_NAME`
- `CONTENT_FIELD_NAME`
- `REGION`
- `AI_LOG_QUEUE_URL`
- `TERRAFORM_LOG_QUEUE_URL`

운영 점검 원칙은 다음이다.

- secret value를 출력하지 않는다.
- key 존재 여부만 확인한다.
- ExternalSecret status와 target Secret 생성 여부를 확인한다.
- pod startup error가 있으면 누락된 key와 연결해 진단한다.

## 10. 배포 순서

최소 권장 배포 순서는 다음이다.

1. GitHub repository variables/secrets 설정
2. GitHub Environment approval rule 설정
3. Terraform backend/bootstrap 준비
4. Terraform fmt/validate/plan 확인
5. Terraform apply 실행
6. ECR repository, RDS, S3, SQS, Secrets Manager, Cognito output 확인
7. backend image build/publish
8. Python analysis service image build/publish
9. frontend build/deploy
10. ArgoCD sync 확인
11. Kubernetes rollout status 확인
12. ExternalSecret / Kubernetes Secret 상태 확인
13. backend health check
14. analysis service health check
15. API smoke test
16. browser E2E test
17. log inspection

## 11. 배포 완료 판단 기준

배포 완료는 단순히 workflow가 성공했다는 의미가 아니다.

다음이 함께 확인되어야 한다.

- Terraform apply가 성공했고 필요한 output이 확인된다.
- ECR에 backend/analysis service image가 push되었다.
- Kubernetes manifest image tag가 해당 image URI로 갱신되었다.
- ArgoCD sync 결과가 정상이다.
- deployment rollout이 성공했다.
- service endpoint가 존재한다.
- ExternalSecret 또는 Kubernetes Secret contract가 충족된다.
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
