# Deployment

## 1. 목적

이 문서는 Terraformers 운영환경 고도화 프로젝트의 현재 배포 가능 범위와 아직 구현되지 않은 목표 구성을 구분한다.

현재 검증된 범위는 Spring Boot backend, React client build, AWS runtime Terraform outputs, Kubernetes backend package, OIDC 기반 AWS workflow 경계다. Frontend S3/CloudFront hosting, 별도 Python analysis service, ArgoCD 자동 동기화는 목표 또는 선행 저장소 참고 범위이며 현재 저장소에서 완료된 운영 구성으로 간주하지 않는다.

## 2. 현재 구현 상태

| 영역 | 현재 저장소 상태 | 배포 전 남은 작업 |
|---|---|---|
| Frontend | React production build 검증 | hosting bucket, CloudFront, API origin routing 계약 추가 |
| Backend | Spring Boot image build, local health, Kubernetes package 검증 | ECR publish 결과와 runtime manifest 연결, live rollout 검증 |
| Analysis | backend 내부 adapter boundary와 비활성 기본값 | Bedrock/OpenSearch/SQS resource·IAM·network·runtime key를 함께 검증한 뒤 선택적으로 활성화 |
| Infrastructure | VPC/EKS/RDS/S3/SQS/ECR/Cognito/IAM/Secrets Manager Terraform source contract | 실제 state, plan, apply, output 값 검증 |
| Runtime Secret | base key, private fallback bundle, External Secrets 정적 전달 계약 검증 | operator 설치 승인, runtime config Secret 초기화, live sync·rotation 검증 |

## 3. 안전 경계

PR 및 정적 preflight에서는 다음을 실행하지 않는다.

- Terraform apply/destroy
- Kubernetes apply
- Docker image push
- External Secrets 설치
- public ALB/Ingress 노출
- Bedrock, OpenSearch, SQS, S3 production adapter 활성화

이 작업들은 영구 금지 대상이 아니라, source contract·권한·network·Secret 전달 경로가 일치한 뒤 승인된 별도 단계에서 수행해야 하는 작업이다.

## 4. 현재 검증 흐름

```text
feature branch
  -> Backend Local Verification
  -> Runtime Contract Verification
       - Spring runtime contract
       - AWS application/Kubernetes/frontend contract
       - Terraform output and GitHub reference inventory
       - AWS runtime input bundle fixture verification
       - External Secrets managed delivery fixture verification
  -> Pre-deployment Package Verification
       - committed frontend lockfile / npm ci / production build
       - backend image build / local health
       - offline Kubernetes package render
  -> Draft PR review
```

workflow 성공은 실제 AWS 배포 성공을 의미하지 않는다.

## 5. Backend image contract

Backend image는 다음 조건을 만족해야 한다.

- `backend/Dockerfile`에서 빌드 가능
- non-root UID `10001`
- application JAR과 고정된 Terraform CLI 포함
- container healthcheck 존재
- local profile로 기동해 `/actuator/health` 정상 응답
- ECR publish 시 Terraform output `backend_image_repository_url`과 동일한 repository 사용
- `latest`가 아닌 immutable tag 또는 digest 사용

AWS credential은 장기 access key가 아니라 GitHub OIDC를 사용한다.

- variable: `AWS_REGION`
- secret: `AWS_ROLE_TO_ASSUME`

## 6. Backend production runtime contract

필수 Secret key는 정확히 다음 8개다.

- `SPRING_DATASOURCE_URL`
- `SPRING_DATASOURCE_USERNAME`
- `SPRING_DATASOURCE_PASSWORD`
- `COGNITO_REGION`
- `COGNITO_USER_POOL_ID`
- `COGNITO_USER_POOL_CLIENT_ID`
- `COGNITO_JWKS_URL`
- `S3_BUCKET_NAME`

`ANALYSIS_RESULT_BUCKET_NAME`은 선택적 override다.

기본 bundle은 disabled adapter용 queue/model/OpenSearch placeholder를 만들지 않는다. Optional adapter key는 해당 adapter를 실제로 활성화하는 별도 변경에서만 추가한다.

## 7. Terraform output 전달 경로

`build-aws-runtime-input-bundle.py`는 다음 Terraform output을 입력으로 사용한다.

| 목적 | Output |
|---|---|
| image repository | `backend_image_repository_url` |
| upload/result bucket | `upload_bucket_name`, `result_bucket_name` |
| runtime Secret container | `backend_runtime_secret_arn` |
| Kubernetes Secret name | `kubernetes_runtime_secret_name` |
| datasource | `spring_datasource_url`, `database_username` |
| managed DB credential pointer | `database_master_user_secret_arn` |
| Cognito | `cognito_region`, `cognito_user_pool_id`, `cognito_user_pool_client_id`, `cognito_jwks_url` |
| EKS/backend IRSA | `cluster_name`, `backend_namespace`, `backend_service_account_name`, `backend_irsa_role_arn` |
| External Secrets IRSA | `external_secrets_service_account_name`, `external_secrets_irsa_role_arn`, `aws_region` |

기존 private fallback bundle은 다음 파일을 생성한다.

```text
artifacts/aws-runtime-input-bundle/
  backend-runtime-secret.env
  aws-runtime-manifest.env
  deployment-source-map.json
  bundle-summary.txt
  apply-order.txt
```

`artifacts/`는 Git에서 제외한다. Secret env와 rendered Secret manifest를 커밋하거나 CI public artifact로 업로드해서는 안 된다.

## 8. Managed Secret delivery contract

Production 기준으로 선택한 전달 방식은 External Secrets Operator다. 원본 인프라와 `rdb-refactor`의 동기화 개념 및 RDS `password` property 매핑을 재사용하되, legacy namespace·key·API와 workload identity 공유는 재사용하지 않는다.

```text
backend runtime Terraform outputs
  -> non-password payload 8 keys
  -> backend_runtime_secret_arn

RDS manage_master_user_password
  -> database_master_user_secret_arn / property password

External Secrets Operator
  -> terraformers-backend-runtime-secrets
  -> backend Deployment envFrom
```

전용 identity:

- namespace: `terraformers-runtime`
- ServiceAccount: `terraformers-external-secrets`
- SecretStore: `terraformers-backend-secretsmanager`
- ExternalSecret: `terraformers-backend-runtime`
- target Secret: `terraformers-backend-runtime-secrets`
- API: `external-secrets.io/v1`

전용 IRSA policy는 두 Secret ARN에 대한 `DescribeSecret`, `GetSecretValue`만 허용한다. DB password는 backend runtime payload, GitHub input, manifest에 복사하지 않는다.

정적 패키지:

```text
artifacts/external-secrets-runtime-package/
  backend-runtime-secret-payload.json
  external-secrets-runtime.yaml
  managed-secret-source-map.json
  package-summary.txt
  apply-order.txt
```

현재는 manifest와 field mapping만 검증한다. External Secrets 설치, Secrets Manager value 변경, Kubernetes apply는 수행하지 않았다.

## 9. Kubernetes package contract

현재 backend package의 canonical identity는 다음과 같다.

- namespace: `terraformers-runtime`
- ServiceAccount: `terraformers-backend`
- ConfigMap: `terraformers-backend-runtime-config`
- Secret: `terraformers-backend-runtime-secrets`
- Deployment/Service: `terraformers-backend`
- profile: `prod`

public-safe template에는 실제 ECR URI, IRSA ARN, Secret 값, Ingress가 없다. private render 단계에서 immutable image와 IRSA role을 주입하고, preflight까지만 자동화한다.

## 10. Frontend contract와 미구현 hosting

Frontend production build에는 다음 공개 값만 전달한다.

- `REACT_APP_API_BASE_URL`
- `REACT_APP_AWS_REGION`
- `REACT_APP_COGNITO_USER_POOL_ID`
- `REACT_APP_COGNITO_USER_POOL_CLIENT_ID`

현재 Terraform inventory에는 frontend hosting bucket과 CloudFront distribution output이 없다. 따라서 S3 sync와 CloudFront invalidation은 현재 완료된 배포 흐름으로 설명하지 않는다. 다음 인프라 단계에서 실제 필요성, 비용, origin routing, backend 접근 방식과 함께 설계한다.

## 11. Optional adapter activation

Bedrock/OpenSearch/SQS/S3 adapter는 base ConfigMap에서 비활성화한다. 활성화 전 다음을 함께 검증한다.

1. Terraform resource와 output
2. EKS workload network path
3. IRSA IAM permission
4. runtime key 전달 방식
5. failure/timeout/retry behavior
6. smoke evidence와 cleanup 기준

리소스가 존재한다는 이유만으로 adapter를 활성화하지 않는다.

## 12. 실제 AWS 배포 전 gate

다음 항목이 모두 명시되어야 한다.

1. GitHub OIDC trust와 role permission
2. Terraform state/backend와 실제 output
3. RDS security group 및 TLS path
4. External Secrets 설치 방식과 live SecretStore/ExternalSecret sync
5. backend runtime Secret non-password payload 초기화 방식
6. ECR image tag/digest와 manifest image 일치
7. backend·External Secrets IRSA trust subject와 ServiceAccount annotation 일치
8. S3 bucket IAM permission
9. frontend hosting/CloudFront/API origin 계약
10. live cluster server-side dry-run
11. rollout, health, authenticated API smoke 및 evidence 수집

이 조건이 충족되기 전에는 실제 apply나 rollout을 시작하지 않는다.

## 13. 완료 판단 기준

프로젝트의 배포 완료는 workflow 성공이나 리소스 생성만으로 판단하지 않는다.

- source contract와 실제 AWS output이 일치함
- Secret key와 application property가 일치함
- workload identity와 IAM permission이 일치함
- immutable image가 실제 Deployment에 반영됨
- rollout과 health가 정상임
- 인증된 업로드·분석·결과 조회 흐름이 검증됨
- 장애 시 원인 구간과 복구 상태를 evidence로 설명할 수 있음

현재 PR은 source/runtime/package와 managed Secret 정적 계약을 정리하는 단계이며, live AWS 검증은 별도 승인 단계다.
