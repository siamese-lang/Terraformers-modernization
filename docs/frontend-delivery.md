# Frontend Delivery Contract

## 1. 목적

React SPA를 단순히 S3에 올리는 수준이 아니라, 브라우저 진입점부터 backend API까지 동일한 운영 경계로 전달한다.

```text
Browser
  -> CloudFront HTTPS
       ├─ static route -> private S3 frontend bucket
       └─ /api/*       -> approved backend load-balancer origin
```

Frontend는 `REACT_APP_API_BASE_URL`을 비워 상대 경로 `/api/*`를 사용한다. 브라우저가 backend origin을 직접 호출하지 않으므로 운영 기본 경로에서는 별도 CORS origin 목록과 mixed-content 문제를 만들지 않는다.

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
- 고정 도메인과 인증서

원본의 전체 error response 치환은 backend 401/403/404도 HTML로 바꿀 수 있다. 현재 구현은 CloudFront Function이 static extensionless route만 `/index.html`로 rewrite하고 `/api` 경로는 제외한다.

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
- S3 bucket policy의 CloudFront service principal + distribution SourceArn 제한

출력:

- `frontend_bucket_name`
- `frontend_bucket_arn`
- `cloudfront_distribution_id`
- `cloudfront_distribution_arn`
- `cloudfront_distribution_domain_name`
- `frontend_base_url`
- `frontend_api_base_url`
- `frontend_origin_access_control_id`

## 4. API 전달 규칙

`/api/*`는 다음 조건을 사용한다.

- viewer HTTPS redirect
- GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE 허용
- managed caching-disabled policy
- Authorization, query string, cookie 등 viewer context 전달
- CloudFront Host header는 backend origin에 전달하지 않음
- SPA rewrite 제외

`/actuator/*`는 public behavior로 만들지 않는다. health 검증은 load balancer target health, cluster 내부 점검, 승인된 운영 경로에서 수행한다.

## 5. Frontend build 입력

생성기:

```text
scripts/deploy/build-frontend-delivery-input-bundle.py
```

입력:

- stateful Terraform output의 Cognito region, pool ID, client ID
- frontend Terraform output의 S3 bucket, CloudFront distribution ID/domain

생성:

```text
frontend-build.env
delivery-source-map.json
bundle-summary.txt
apply-order.txt
```

브라우저 build variable은 네 개뿐이다.

- `REACT_APP_API_BASE_URL` — 빈 값, same-origin 사용
- `REACT_APP_AWS_REGION`
- `REACT_APP_COGNITO_USER_POOL_ID`
- `REACT_APP_COGNITO_USER_POOL_CLIENT_ID`

password, AWS credential, bucket write credential은 frontend build에 포함하지 않는다.

## 6. 배포와 롤백 경계

생성된 `apply-order.txt`는 수동 승인 이후의 명령 순서만 제공한다.

```text
npm ci
npm run build
aws s3 sync --delete
aws cloudfront create-invalidation
```

현재 PR은 이 명령을 실행하지 않는다.

운영 배포에서는 다음 evidence를 남긴다.

- source commit SHA
- frontend lockfile digest
- build variable key 목록
- S3 sync 대상 bucket
- CloudFront distribution ID
- invalidation ID와 완료 상태
- browser/API smoke 결과

S3 versioning은 직전 object version을 보존한다. rollback은 검증된 이전 build를 다시 sync하고 새 invalidation을 생성하는 방식으로 수행하며, 임의 object 단건 복구에 의존하지 않는다.

## 7. 배포 후 smoke 기준

```text
GET /                         -> 200 text/html
GET /projects/<id>            -> 200 text/html, SPA route 유지
GET /api/public-projects      -> JSON, CloudFront cache MISS/비캐싱
POST /api/upload without JWT  -> 401/403 JSON, index.html 치환 금지
OPTIONS /api/upload           -> backend preflight 응답, text/html 금지
GET /actuator/health          -> public backend health route로 사용하지 않음
```

인증 후에는 업로드, project/file ID 생성, 분석 작업, 생성 Terraform 조회, 공개 프로젝트 조회까지 browser E2E로 이어서 검증한다.

## 8. 아직 남은 실제 AWS 조건

Frontend delivery Terraform이 있어도 backend origin이 없으면 서비스는 완성되지 않는다.

다음 단계에서 결정해야 한다.

- CloudFront가 접근할 backend load-balancer 유형과 DNS
- public origin을 사용할 경우 CloudFront 이외 직접 접근 제한 방식
- private origin을 사용할 경우 CloudFront VPC origin 및 load-balancer 연계 가능성
- TLS 인증서와 origin protocol
- EKS Service/Ingress와 target health
- timeout, upload size, streaming/WebSocket 필요 여부

public ALB/Ingress, controller 설치, DNS 변경은 별도 승인 전에는 추가하거나 적용하지 않는다.
