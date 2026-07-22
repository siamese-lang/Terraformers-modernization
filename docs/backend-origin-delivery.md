# Private Backend Origin Delivery

## 1. 목적

이 문서는 CloudFront의 same-origin `/api/*` 요청을 EKS backend까지 전달하는 private origin 계약과 실제 운영 검증 순서를 정의한다.

현재 저장소가 검증하는 범위는 source contract, IAM/네트워크 경계, Kubernetes/Helm template, Terraform schema, fixture package다. AWS Load Balancer Controller 설치, Ingress apply, ALB 생성, CloudFront VPC origin 생성은 아직 실행하지 않았다.

## 2. 최종 경로

```text
Browser
  -> CloudFront HTTPS
       ├─ /*     -> private S3 through OAC/SigV4
       └─ /api/* -> CloudFront VPC origin
                      -> internal ALB :80
                           -> Pod IP :8080
                                -> terraformers-backend ClusterIP/Pods
```

CloudFront만 public entry point다. Backend ALB는 `internal`이고 Kubernetes Service는 `ClusterIP`을 유지한다. 별도 public ALB, public NLB, public Ingress endpoint를 만들지 않는다.

## 3. 원본에서 재사용한 것과 폐기한 것

재사용:

- CloudFront에서 `/api/*`를 backend origin으로 분리하는 서비스 흐름
- EKS에서 load balancer를 통해 Spring backend로 전달하는 구조
- AWS Load Balancer Controller 기반 Kubernetes reconciliation
- ALB health check를 Spring Actuator로 수행하는 운영 관점

폐기·개선:

- internet-facing load balancer
- CloudFront public custom origin
- domain 이름을 코드에 고정하는 방식
- `/actuator/*` public routing
- backend workload와 controller의 IAM identity 공유
- controller policy의 임의 축약본

## 4. Network contract

기반 VPC는 다음을 만족한다.

- 두 개 이상의 private subnet
- private subnet의 `kubernetes.io/role/internal-elb=1` 태그
- EKS node group과 backend Pod가 private subnet에 위치
- CloudFront VPC origin 자격을 위한 VPC Internet Gateway 존재
- ALB frontend security group의 ingress는 AWS-managed CloudFront origin-facing prefix list에서 오는 TCP 80만 허용
- ALB frontend security group의 egress는 runtime VPC CIDR의 TCP 8080만 허용

Internet Gateway는 CloudFront VPC origin의 VPC 자격 조건을 충족하기 위한 리소스이며 private ALB를 internet-facing으로 바꾸지 않는다.

## 5. Controller identity

AWS Load Balancer Controller는 backend ServiceAccount와 분리한 전용 identity를 사용한다.

```text
namespace: kube-system
serviceAccount: aws-load-balancer-controller
IRSA role: eks-runtime.load_balancer_controller_irsa_role_arn
chart: eks/aws-load-balancer-controller 3.4.2
```

IAM policy source는 controller 3.4.2 기준 공식 policy를 repository에 고정한다.

```text
infra/terraform/envs/eks-runtime/policies/aws-load-balancer-controller-v3.4.2.json
```

정적 gate는 JSON parse 결과와 SHA256을 evidence로 남긴다. Controller 버전 변경 시 chart version, policy file, checksum, verification summary를 같은 변경에서 갱신해야 한다.

## 6. Kubernetes Ingress contract

Ingress 이름:

```text
terraformers-runtime/terraformers-backend-origin
```

핵심 annotation:

```text
scheme=internal
target-type=ip
security-groups=<Terraform-managed frontend SG>
manage-backend-security-group-rules=true
listener=HTTP:80
backend-protocol=HTTP
healthcheck=/actuator/health
```

Listener route는 `/api` Prefix 하나만 제공한다. `/actuator`는 target health check에만 사용하며 public listener route가 아니다.

`target-type=ip`를 사용하므로 ALB target group은 node port가 아니라 backend Pod IP를 직접 등록한다. Controller는 지정한 frontend security group과 backend Pod/ENI security-group rule을 함께 reconcile해야 한다.

## 7. CloudFront VPC origin contract

Frontend Terraform은 controller가 생성한 ALB ARN을 입력으로 받는다.

```text
api_origin_load_balancer_arn
```

Terraform precondition:

- load balancer는 `internal`
- load balancer type은 `application`

CloudFront VPC origin은 ALB의 HTTP 80 listener에 연결한다. Viewer 구간은 CloudFront HTTPS이고 VPC origin 구간은 AWS private network의 HTTP다. 현재 단계에서 내부 TLS 인증서·갱신·hostname 검증 복잡성을 추가하지 않는다.

`/api/*` behavior:

- cache disabled
- Authorization/query/cookie forwarding
- Host header 제외
- GET/HEAD/OPTIONS/POST/PUT/PATCH/DELETE 허용
- SPA error rewrite 대상에서 제외

## 8. 생성되는 package

```text
artifacts/backend-origin-package/
  aws-load-balancer-controller-serviceaccount.yaml
  aws-load-balancer-controller-values.yaml
  backend-origin-ingress.yaml
  backend-origin-source-map.json
  package-summary.txt
  apply-order.txt
```

생성기:

```text
scripts/deploy/build-backend-origin-package.py
```

입력은 EKS Terraform output JSON이다. 생성기는 AWS 인증, Helm install, Kubernetes apply, load balancer 생성, CloudFront mutation을 수행하지 않는다.

## 9. 승인 후 실제 적용 순서

다음 순서는 별도 승인 후에만 수행한다.

1. EKS/network/runtime dependency Terraform plan 검토
2. Terraform apply 후 controller IRSA와 frontend security group output 확보
3. backend origin package 생성
4. controller ServiceAccount apply
5. pinned chart 3.4.2 install
6. controller rollout 완료 확인
7. backend Deployment와 ClusterIP Service rollout 확인
8. internal Ingress apply
9. Ingress hostname과 ALB ARN 확인
10. ALB scheme, subnet, security group, target health 확인
11. ALB ARN을 frontend-delivery Terraform input으로 전달
12. CloudFront VPC origin/distribution plan 검토 및 apply
13. frontend build/S3 sync/invalidation
14. browser/API E2E와 장애 시나리오 검증

## 10. Live validation evidence

### Controller

```text
kubectl get deployment aws-load-balancer-controller -n kube-system
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system
kubectl logs deployment/aws-load-balancer-controller -n kube-system --tail=200
```

Evidence:

- controller image/version
- ServiceAccount annotation
- IRSA role ARN
- rollout 상태
- reconciliation error 유무

### Ingress와 ALB

```text
kubectl describe ingress terraformers-backend-origin -n terraformers-runtime
aws elbv2 describe-load-balancers --names <internal-alb-name>
aws elbv2 describe-target-groups --load-balancer-arn <alb-arn>
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

정상 기준:

- scheme `internal`
- type `application`
- private subnet 두 개 이상
- frontend SG가 CloudFront managed prefix list만 허용
- target type `ip`
- 모든 active backend Pod target이 healthy
- health path `/actuator/health`

### CloudFront/browser

```text
GET /
GET /projects/<id>
GET /api/public-projects
POST /api/upload without token
OPTIONS /api/upload
```

정상 기준:

- `/`와 SPA deep link는 React HTML
- `/api/public-projects`는 JSON
- 인증 없는 보호 API는 JSON 401/403
- OPTIONS는 HTML로 치환되지 않음
- API 응답에 cache hit가 발생하지 않음
- ALB DNS로 직접 인터넷 접근할 수 없음

## 11. 장애 시나리오

### Scenario A — Pod readiness failure

재현:

- backend Pod가 readiness를 통과하지 못하는 상태를 만든다.

관찰:

- target health가 unhealthy로 변하는지
- CloudFront `/api/*`가 502/503을 보존하는지
- SPA `index.html`로 치환되지 않는지

복구:

- 정상 image/config로 rollout
- target healthy 복귀
- API JSON 응답 정상화

### Scenario B — Security group drift

재현:

- 승인된 실습 환경에서 ALB-to-Pod 8080 rule을 제거한다.

관찰:

- target health timeout
- controller reconciliation log
- CloudFront 502/504

복구:

- controller-managed rule 복원
- target healthy 확인
- API smoke 재실행

### Scenario C — Wrong health check path

재현:

- healthcheck path를 존재하지 않는 경로로 변경한다.

관찰:

- ALB는 생성되지만 target이 unhealthy
- Pod 자체 health와 ALB target health가 다름

복구:

- `/actuator/health` 복원
- target health와 CloudFront API 경로 재검증

### Scenario D — Controller unavailable

재현:

- 승인된 실습 환경에서 controller replica를 0으로 조정한다.

관찰:

- 기존 ALB traffic과 신규 reconciliation을 구분
- Ingress 변경이 반영되지 않음
- controller rollout/log evidence

복구:

- controller replica 복원
- reconciliation 완료와 ALB attribute 확인

## 12. Rollback 기준

Backend application rollback:

- Deployment image digest를 직전 검증 digest로 복구
- rollout 완료
- target health와 authenticated smoke 재검증

Ingress rollback:

- 직전 검증된 rendered Ingress artifact 적용
- ALB listener/target group drift 확인

CloudFront rollback:

- 직전 검증 distribution config 또는 Terraform state 기준으로 복구
- `/api/*` VPC origin과 cache-disabled policy 확인

Controller rollback:

- chart와 IAM policy를 독립적으로 임의 downgrade하지 않는다.
- 검증된 chart/policy pair로 함께 복구한다.

## 13. 현재 완료·미완료 구분

완료:

- private ALB/VPC origin source contract
- dedicated controller IRSA
- pinned controller policy/chart contract
- internal/IP-target Ingress template
- CloudFront-managed prefix-list SG contract
- package renderer와 cluster-free CI evidence
- Terraform static validation

미완료:

- controller 실제 설치
- internal ALB 실제 생성
- Pod target health 확인
- CloudFront VPC origin 실제 생성
- browser E2E
- 장애·복구 live evidence

따라서 현재 결과는 운영환경 설계와 배포 전 통제 수준을 입증하지만, live 운영 완료로 표현하지 않는다.
