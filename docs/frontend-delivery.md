# Frontend Delivery Contract

## 1. 목적

React SPA를 단순히 S3에 올리는 수준이 아니라, 브라우저 진입점부터 EKS backend까지 하나의 운영 경계로 전달한다.

```text
Browser
  -> CloudFront HTTPS
       ├─ static route -> private S3 frontend bucket through OAC/SigV4
       └─ /api/*       -> CloudFront VPC origin
                            -> internal ALB :80
                                 -> backend Pod IP :8080
```

Frontend는 `REACT_APP_API_BASE_URL`을 비워 상대 경로 `/api/*`를 사용한다. 브라우저가 backend ALB를 직접 호출하지 않으므로 운영 기본 경로에서 별도 cross-origin API URL과 public backend endpoint를 만들지 않는다.

## 2. 기존 구현 재사용 판단

원본 `Infra-code`에서 재사용한 의도:

- S3에 React build artifact 저장
- CloudFront를 사용자 진입점으로 사용
- `/api/*`를 backend origin으로 전달
- SPA deep-link 처리
- distribution ID를 배포 후 invalidation에 사용

그대로 재사용하지 않은 구현:

- CloudFront OAI
- public access block 완화
- wildcard S3 CORS
- distribution 전체 403/404를 `index.html`로 치환
- API GET 응답의 장시간 캐싱
- `/actuator/*` public behavior
- public custom origin과 고정 backend domain
- internet-facing ALB/NLB

현재 구현은 CloudFront Function이 static extensionless route만 `/index.html`로 rewrite하고 `/api` 경로는 제외한다. Backend origin은 public DNS endpoint가 아니라 controller가 생성한 internal ALB를 CloudFront VPC origin으로 연결한다.

## 3. 현재 Terraform 계약

환경:

```text
infra/terraform/envs/frontend-delivery
```

핵심 리소스:

- private S3 bucket
- BucketOwnerEnforced
- public access block 전체 활성화
- AES256 server-side encryption
- versioning과 noncurrent version retention
- CloudFront Origin Access Control, SigV4 always
- CloudFront Function 기반 SPA rewrite
- static cache optimized behavior
- `/api/*` caching-disabled behavior
- CloudFront VPC origin
- internal Application Load Balancer ARN validation
- S3 bucket policy의 CloudFront service principal + distribution SourceArn 제한
- GitHub Actions frontend delivery 전용 IAM role

Backend origin 입력:

```text
api_origin_load_balancer_arn
```

Terraform은 입력 load balancer가 다음 조건을 만족하는지 확인한다.

- scheme: internal
- type: application

CloudFront-to-ALB 구간은 private HTTP 80 listener를 사용한다. Viewer 구간은 CloudFront HTTPS다. Internal ALB 생성과 security-group 경계는 `docs/backend-origin-delivery.md`를 따른다.

출력:

- `frontend_bucket_name`
- `frontend_bucket_arn`
- `cloudfront_distribution_id`
- `cloudfront_distribution_arn`
- `cloudfront_distribution_domain_name`
- `frontend_base_url`
- `frontend_api_base_url`
- `frontend_origin_access_control_id`
- `backend_vpc_origin_id`
- `backend_origin_load_balancer_arn`
- `backend_origin_load_balancer_dns_name`
- `frontend_delivery_role_arn`
- `frontend_delivery_role_name`
- `github_environment_name`

## 4. API 전달 규칙

`/api/*`는 다음 조건을 사용한다.

- viewer HTTPS redirect
- GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE 허용
- managed caching-disabled policy
- Authorization, query string, cookie 등 viewer context 전달
- CloudFront Host header는 backend origin에 전달하지 않음
- SPA rewrite 제외
- internal ALB VPC origin만 사용

`/actuator/*`는 public behavior로 만들지 않는다. `/actuator/health`는 ALB target health check와 cluster 내부 검증에만 사용한다.

## 5. Frontend build 입력

생성기:

```text
scripts/deploy/build-frontend-delivery-input-bundle.py
```

입력:

- stateful Terraform output의 Cognito region, pool ID, client ID
- frontend Terraform output의 frontend delivery role ARN, S3 bucket, CloudFront distribution ID/domain

생성:

```text
frontend-build.env
delivery-source-map.json
bundle-summary.txt
apply-order.txt
github-environment-variables.env
```

브라우저 build variable은 네 개뿐이다.

- `REACT_APP_API_BASE_URL` — 빈 값, same-origin 사용
- `REACT_APP_AWS_REGION`
- `REACT_APP_COGNITO_USER_POOL_ID`
- `REACT_APP_COGNITO_USER_POOL_CLIENT_ID`

Password, AWS access key, secret, JWT, Authorization header, bucket write credential, internal ALB ARN/DNS는 frontend bundle에 포함하지 않는다. `github-environment-variables.env`에는 secret이 아닌 `FRONTEND_AWS_ROLE_TO_ASSUME`, `FRONTEND_BUCKET_NAME`, `CLOUDFRONT_DISTRIBUTION_ID` 설정값만 포함한다.

## 6. 배포와 롤백 경계

Guarded workflow:

```text
.github/workflows/frontend-delivery.yml
```

기본값은 `deploy_frontend=false`다. 기본 실행은 production build와 digest evidence만 만들고 AWS credential을 구성하지 않는다.

명시적으로 승인한 배포에서는 `allowed-account-ids`와 `EXPECTED_AWS_ACCOUNT_ID` caller 확인을 통과해야 한다. `aws_role_to_assume` 임의 input과 장기 AWS access key secret은 사용하지 않는다.

명시적으로 승인한 배포에서는:

1. GitHub Environment `frontend-delivery`에서 foundation의 기존 `token.actions.githubusercontent.com` provider를 신뢰하는 `FRONTEND_AWS_ROLE_TO_ASSUME` role 확인
2. reproducible frontend build
3. mutable entrypoint sync
4. immutable hashed asset sync
5. 제한된 CloudFront invalidation
6. invalidation 완료 대기
7. delivery evidence upload

Cache policy:

```text
index.html, asset-manifest.json, manifest.json
  -> no-cache,no-store,must-revalidate

static/js, static/css, static/media
  -> public,max-age=31536000,immutable
```

Invalidation 범위:

```text
/
/index.html
/asset-manifest.json
/manifest.json
```

`/*` 전체 invalidation은 사용하지 않는다.

운영 evidence:

- source commit SHA
- frontend lockfile와 build file digest
- build variable key 목록
- S3 bucket
- CloudFront distribution ID
- cache-control 정책
- invalidation ID와 완료 상태
- browser/API smoke 결과

S3 versioning은 이전 object version을 보존한다. Rollback은 검증된 이전 build 전체를 다시 sync하고 새 invalidation을 생성하는 방식으로 수행한다.

## 7. 배포 후 smoke 기준

```text
GET /                         -> 200 text/html
GET /projects/<id>            -> 200 text/html, SPA route 유지
GET /api/public-projects      -> JSON, API cache 비활성
POST /api/upload without JWT  -> 401/403 JSON, index.html 치환 금지
OPTIONS /api/upload           -> backend preflight 응답, text/html 금지
GET /actuator/health          -> public CloudFront route로 사용하지 않음
```

인증 후에는 업로드, project/file ID 생성, 분석 작업, 생성 Terraform 조회, 공개 프로젝트 조회까지 browser E2E로 이어서 검증한다.

추가 network 기준:

- internal ALB DNS는 인터넷에서 직접 접근할 수 없어야 한다.
- ALB frontend SG는 CloudFront origin-facing managed prefix list만 허용해야 한다.
- ALB target은 Pod IP이며 healthy 상태여야 한다.
- Backend 401/403/404/5xx가 SPA HTML로 변환되지 않아야 한다.

## 8. 현재 완료·미완료 구분

완료:

- private S3/OAC source contract
- CloudFront VPC origin Terraform contract
- internal ALB ARN/type/scheme validation
- same-origin `/api/*`와 API cache-disabled contract
- frontend input bundle
- guarded OIDC delivery workflow
- Terraform-managed frontend delivery OIDC role contract
- foundation GitHub OIDC provider ARN input reuse contract
- split cache policy와 limited invalidation
- cluster/AWS mutation 없는 CI evidence

미완료:

- internal ALB 실제 생성
- CloudFront VPC origin 실제 생성
- Terraform apply로 frontend delivery IAM role 실제 생성
- GitHub Environment variable 실제 설정
- S3 frontend sync
- CloudFront invalidation live evidence
- browser/API E2E
- frontend rollback live evidence

Public ALB/Ingress, controller 설치, Terraform apply, S3 sync, CloudFront mutation은 별도 승인 전에는 수행하지 않는다.
