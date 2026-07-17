# Live AWS Deployment Execution Plan

## 1. 목적

정적 source/runtime/package 계약이 통과한 뒤 실제 AWS 배포를 한 번에 실행하지 않고 다음 순서로 진행한다.

```text
account and identity verification
  -> foundation plan review
  -> explicit foundation apply approval
  -> foundation post-apply verification
  -> bootstrap state migration to versioned S3
  -> protected GitHub environment configuration
  -> strict prerequisite inventory
  -> stage-by-stage Terraform plan and approval
  -> deployment, verification, recovery, and cleanup evidence
```

현재 저장소 workflow는 plan과 검증까지만 자동화한다. `terraform apply`, `terraform destroy`, `kubectl apply`, Helm install/upgrade, image push, S3 sync, CloudFront invalidation은 자동 실행하지 않는다.

## 2. 최종 서비스 경로

```text
Browser
  -> CloudFront HTTPS
       ├─ static -> private versioned S3 through OAC/SigV4
       └─ /api/* -> CloudFront VPC origin
                       -> internal ALB :80
                            -> backend Pod IP :8080
                                 -> RDS / S3 / Cognito
```

Public entry point는 CloudFront 하나다. Internet-facing ALB, public backend DNS, public `/actuator/*` route는 허용하지 않는다.

## 3. State 및 identity 기준

Canonical prerequisite contract:

```text
config/live-aws-prerequisites.json
```

고정 기준:

```text
Terraform CLI             1.15.8
AWS region                ap-northeast-2
state backend             private versioned S3
state locking             S3 native .tflock
DynamoDB lock table       not used
GitHub authentication     protected environment + OIDC
GitHub environment        aws-live-plan
state prefix              terraformers-modernization/dev
```

Required GitHub environment variables:

```text
AWS_REGION
AWS_ROLE_TO_ASSUME
AWS_TERRAFORM_STATE_BUCKET
AWS_TERRAFORM_STATE_PREFIX
```

Required GitHub environment secrets:

```text
AWS_LIVE_NETWORK_TFVARS_B64
AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64
AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64
AWS_LIVE_EKS_TFVARS_B64
AWS_LIVE_FRONTEND_TFVARS_B64
```

별도 lock table 변수는 사용하지 않는다. Backend init은 `use_lockfile=true`를 사용한다.

Stage state key 규칙:

```text
<AWS_TERRAFORM_STATE_PREFIX>/<plan_stage>/terraform.tfstate
```

예:

```text
terraformers-modernization/dev/network/terraform.tfstate
terraformers-modernization/dev/eks-runtime/terraform.tfstate
```

## 4. Foundation bootstrap

Terraform directory:

```text
infra/terraform/bootstrap/aws-live-foundation
```

Foundation 생성 대상:

- versioning이 활성화된 private S3 state bucket
- S3 public access block
- TLS-only bucket policy
- AES256 server-side encryption
- S3 native state 및 `.tflock` object 권한
- 기존 GitHub IAM OIDC provider 재사용 또는 신규 생성
- `aws-live-plan` environment subject만 신뢰하는 Terraform plan role
- AWS `ReadOnlyAccess` 및 state prefix 한정 write 권한

Foundation은 최초 1회 local state로 시작한다. 다음 순서를 바꾸지 않는다.

1. exact AWS account와 기존 OIDC provider를 확인한다.
2. private bootstrap tfvars를 저장소 밖에 작성한다.
3. `scripts/deploy/plan-live-foundation.sh`로 plan을 생성하고 검증한다.
4. create-only resource set, role trust, S3 보호 설정, binary plan digest를 검토한다.
5. 사용자가 foundation apply를 명시적으로 승인한다.
6. 검토한 binary plan만 apply한다.
7. AWS API와 Terraform output으로 생성 결과를 읽기 전용 검증한다.
8. local bootstrap state의 백업을 만든다.
9. private backend configuration을 작성한다.
10. `terraform init -migrate-state`로 bootstrap state를 생성된 S3 backend로 이전한다.
11. remote state와 local backup의 resource address를 비교한다.
12. migration 후 plan이 `No changes`인지 확인한다.

Foundation apply와 state migration은 같은 작업으로 취급하지 않는다. Apply 검증이 끝나기 전에 state migration을 시작하지 않는다.

## 5. Foundation apply 승인 조건

Foundation apply는 다음 조건이 모두 충족된 경우에만 승인 대상으로 본다.

1. PR head와 local head가 일치한다.
2. 최신 8개 automatic verification workflow가 모두 성공한다.
3. `scripts/deploy/plan-live-foundation.sh` 결과가 `apply-review-ready`다.
4. OIDC provider mode가 실제 AWS inventory와 일치한다.
5. plan이 예상된 foundation resource만 포함한다.
6. 모든 managed action이 `create`다.
7. delete, update, replacement가 없다.
8. expected AWS account와 caller account가 일치한다.
9. state bucket 이름, region, prefix가 검토값과 일치한다.
10. `force_destroy=false`, public access block, versioning, encryption이 확인된다.
11. role trust subject와 audience가 exact match다.
12. binary plan은 저장소 밖에 있으며 plan 이후 source/tfvars가 변경되지 않았다.
13. 사용자가 apply 실행을 명시적으로 승인한다.

`allow_destructive=true`는 일반 apply 허용 스위치가 아니다. 데이터 이전·백업·복구 계획이 있는 별도 변경에서만 검토한다.

## 6. Foundation 사후 검증

Apply 직후 다음을 읽기 전용으로 확인한다.

```text
STS caller account
S3 bucket existence and region
S3 versioning Enabled
S3 public access block all true
S3 default encryption AES256
S3 bucket policy denies insecure transport
IAM plan role existence
IAM role trust subject and audience
ReadOnlyAccess attachment
state prefix object permissions
Terraform outputs
```

사후 검증 중 하나라도 실패하면 GitHub environment 또는 후속 Terraform stage를 구성하지 않는다. 먼저 실제 리소스와 local state의 일치 여부를 조사한다.

## 7. Bootstrap state migration

Private backend configuration은 다음 계약을 사용한다.

```hcl
bucket       = "<created-state-bucket>"
key          = "terraformers-modernization/dev/bootstrap/terraform.tfstate"
region       = "ap-northeast-2"
encrypt      = true
use_lockfile = true
```

Migration 전:

- local `terraform.tfstate`와 backup을 저장소 밖에 보관한다.
- `terraform state list`를 기록한다.
- state serial과 lineage를 기록한다.
- bucket versioning과 native lockfile 권한을 재확인한다.

Migration 후:

- remote backend init 성공
- remote state object 존재
- state version 생성
- `terraform state list` address 동일
- `terraform plan` 결과 `No changes`
- local raw state와 backend configuration 미커밋

State migration 실패 시 local state를 삭제하지 않는다. 원격 object와 local backup을 모두 보존하고 원인을 확인한다.

## 8. GitHub 보호 환경

Foundation output과 state migration이 확정된 뒤 `aws-live-plan` environment를 구성한다.

권장 protection:

- deployment branch는 배포 시점의 승인된 branch만 허용
- required reviewer 설정
- administrator bypass 비활성 또는 사용 금지
- environment variable과 Secret은 environment scope에 저장

Role ARN은 credential이 아니므로 variable로 저장한다. Private tfvars plaintext와 base64 값은 console output, workflow artifact, issue, PR에 붙이지 않는다.

## 9. 단계 구조

Canonical stage manifest:

```text
config/live-deployment-stages.json
```

단계:

1. `00-state-and-identity-preflight`
2. `10-network-plan`
3. `20-runtime-dependencies-plan`
4. `30-stateful-dependencies-plan`
5. `40-eks-runtime-plan`
6. `50-image-publish`
7. `60-cluster-operators-and-secrets`
8. `70-backend-rollout`
9. `80-private-origin-reconciliation`
10. `90-frontend-delivery-plan`
11. `100-frontend-publish`
12. `110-e2e-and-incident-evidence`

Terraform plan selector:

| Selector | Terraform directory | 선행 조건 |
|---|---|---|
| `network` | `infra/terraform/envs/aws-runtime-network` | foundation/state/environment strict inventory |
| `runtime-dependencies` | `infra/terraform/envs/backend-runtime-dependencies` | network plan/apply output review |
| `stateful-dependencies` | `infra/terraform/envs/backend-stateful-dependencies` | network/runtime output review |
| `eks-runtime` | `infra/terraform/envs/eks-runtime` | network/runtime/stateful output review |
| `frontend-delivery` | `infra/terraform/envs/frontend-delivery` | healthy controller-created internal ALB ARN |

`frontend-delivery`는 internal ALB ARN이 실제 AWS에 존재한 뒤에만 계획한다.

## 10. Guarded plan workflow

Workflow:

```text
.github/workflows/aws-live-terraform-plan.yml
```

기본 실행:

```text
execute_live_plan=false
```

실제 plan 실행 입력:

```text
execute_live_plan=true
expected_aws_account_id=<12 digit account ID>
plan_stage=<one of five selectors>
allow_destructive=false
allow_optional_adapters=false
```

실제 plan job은 protected environment 승인, OIDC role assumption, account/S3 backend 검증, private tfvars decode, S3 backend init, validate, saved plan, risk 분석, sanitized evidence 생성, raw input 삭제 순서로 동작한다.

## 11. Plan risk gate

기본 차단 항목:

- delete 또는 replacement
- internet-facing ALB
- `0.0.0.0/0` 또는 `::/0` ingress
- publicly accessible RDS
- S3 public access block 완화
- EKS endpoint CIDR 전체 공개
- Bedrock/OpenSearch optional adapter resource

Cost-bearing resource는 별도로 표시한다.

- EKS cluster/node group
- RDS instance
- NAT Gateway
- ALB
- CloudFront distribution
- EC2 instance
- OpenSearch collection/domain

이 목록은 가격 계산 결과가 아니다. 각 apply 승인 전 월 비용 상한과 validation window를 별도로 확인한다.

## 12. Sensitive evidence boundary

다음 raw plan material을 artifact로 업로드하지 않는다.

```text
private tfvars
base64 private tfvars
backend.hcl
Terraform binary plan
raw terraform show JSON
local or remote tfstate
```

업로드 가능한 것은 caller account, checksum, provider lock checksum, resource action summary, risk count처럼 secret을 포함하지 않는 sanitized evidence뿐이다.

## 13. 단계별 중단 기준

### Network

- public ingress 확대
- 예상하지 않은 추가 NAT Gateway
- subnet/route replacement
- internal load balancer tag 제거

### Runtime dependencies

- S3 public access
- ECR repository replacement
- runtime Secret payload에 password 포함
- optional adapter resource 등장

### Stateful dependencies

- RDS delete/replacement
- publicly accessible database
- storage 축소
- RDS-managed password 계약 변경

### EKS runtime

- cluster/node group replacement
- endpoint public CIDR 확대
- backend/External Secrets/controller IRSA trust 혼합
- private origin SG public exposure

### Frontend delivery

- public custom origin
- internet-facing 또는 non-ALB origin
- CloudFront distribution replacement
- API caching 활성화
- distribution-wide error substitution

## 14. Rollback 원칙

- Network/EKS/RDS replacement는 일반 배포 rollback으로 처리하지 않는다.
- Backend는 이전 known-good image digest로 되돌린다.
- Kubernetes rollout은 이전 ReplicaSet으로 복구한다.
- Controller는 이전 Helm revision으로 rollback한다.
- Frontend는 이전 검증 build를 다시 배포한다.
- DB migration은 애플리케이션 rollback과 분리하며 검증되지 않은 down migration을 자동 실행하지 않는다.
- 장애 evidence를 수집하기 전에 리소스를 삭제하지 않는다.

## 15. 최종 live evidence

실제 운영 경험 포트폴리오로 인정하려면 다음 evidence가 필요하다.

- foundation apply와 state migration 검증
- 각 Terraform stage plan digest와 sanitized risk summary
- apply 전후 output 차이
- ECR image digest와 Deployment digest 일치
- ExternalSecret sync와 target Secret key 확인
- internal ALB target health
- CloudFront VPC origin 상태
- authenticated browser E2E
- 401/403/404 JSON 보존
- API cache 비활성 확인
- controlled readiness 또는 dependency failure
- 계층별 원인 확인, 복구, 재검증 타임라인
- frontend/backend rollback evidence

Workflow 성공만으로 실제 운영 완료를 주장하지 않는다.
