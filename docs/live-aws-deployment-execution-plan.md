# Live AWS Deployment Execution Plan

## 1. 목적

정적 source/runtime/package 계약이 모두 통과한 뒤, 실제 AWS 배포를 한 번에 실행하지 않고 **계정 확인 → 원격 state 확인 → 단계별 Terraform plan → 명시적 승인 → 배포·검증·복구** 순서로 진행한다.

현재 저장소가 자동화하는 범위는 다음까지다.

```text
repository contract
  -> protected GitHub environment
  -> GitHub OIDC
  -> expected AWS account verification
  -> versioned S3 remote state + DynamoDB lock verification
  -> selected Terraform environment plan
  -> sanitized risk evidence
```

현재 workflow에는 `terraform apply`, `terraform destroy`, `kubectl apply`, Helm install/upgrade, image push, S3 sync, CloudFront invalidation이 없다.

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

## 3. 단계 구조

Canonical stage manifest:

```text
config/live-deployment-stages.json
```

생성기:

```text
scripts/deploy/build-live-deployment-execution-plan.py
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

Terraform plan이 가능한 환경은 다섯 개다.

| Selector | Terraform directory | 선행 조건 |
|---|---|---|
| `network` | `infra/terraform/envs/aws-runtime-network` | AWS account/state preflight |
| `runtime-dependencies` | `infra/terraform/envs/backend-runtime-dependencies` | network plan review |
| `stateful-dependencies` | `infra/terraform/envs/backend-stateful-dependencies` | network/runtime dependency review |
| `eks-runtime` | `infra/terraform/envs/eks-runtime` | network/runtime/stateful review |
| `frontend-delivery` | `infra/terraform/envs/frontend-delivery` | internal ALB가 실제로 존재하고 ARN이 확정됨 |

`frontend-delivery`는 Ingress 적용 전에는 계획할 수 없다. CloudFront VPC origin이 참조할 internal ALB ARN이 실제 AWS에 존재해야 하기 때문이다.

## 4. GitHub 보호 환경

실제 AWS plan job은 다음 protected environment를 사용한다.

```text
aws-live-plan
```

GitHub repository settings에서 이 environment에 required reviewer를 설정한다. PR workflow나 기본 contract job은 AWS credential을 받지 않으며, `execute_live_plan=true`인 manual dispatch만 environment approval을 거친다.

### Required environment/repository variables

```text
AWS_REGION=ap-northeast-2
AWS_TERRAFORM_STATE_BUCKET=<versioned-state-bucket>
AWS_TERRAFORM_LOCK_TABLE=<dynamodb-lock-table>
AWS_TERRAFORM_STATE_PREFIX=terraformers-modernization/dev
```

### Required environment secrets

```text
AWS_ROLE_TO_ASSUME
AWS_LIVE_NETWORK_TFVARS_B64
AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64
AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64
AWS_LIVE_EKS_TFVARS_B64
AWS_LIVE_FRONTEND_TFVARS_B64
```

Stage tfvars는 로컬 `.tfvars` 파일을 UTF-8로 작성한 뒤 base64로 저장한다. Secret 값이나 DB password를 tfvars에 넣지 않는다. DB password source는 계속 RDS-managed Secret이다.

PowerShell 예시:

```powershell
$Bytes = [System.IO.File]::ReadAllBytes("infra\terraform\private\network.tfvars")
[Convert]::ToBase64String($Bytes) | Set-Clipboard
```

붙여넣은 값은 해당 GitHub environment secret에 저장한다. 원본 private tfvars와 base64 값은 저장소에 커밋하지 않는다.

## 5. Remote state prerequisite

Live plan은 다음을 시작 전에 확인한다.

- STS caller account가 dispatch 입력 `expected_aws_account_id`와 일치
- `AWS_TERRAFORM_STATE_BUCKET` 접근 가능
- state bucket versioning `Enabled`
- `AWS_TERRAFORM_LOCK_TABLE` 상태 `ACTIVE`
- stage별 state key가 분리됨

State key 규칙:

```text
<AWS_TERRAFORM_STATE_PREFIX>/<plan_stage>/terraform.tfstate
```

예:

```text
terraformers-modernization/dev/network/terraform.tfstate
terraformers-modernization/dev/eks-runtime/terraform.tfstate
```

State bucket 또는 lock table이 아직 없다면 live plan을 실행하지 않는다. 별도 bootstrap 절차로 먼저 생성하고, 생성 evidence와 소유 계정을 확인해야 한다.

## 6. Guarded plan workflow

Workflow:

```text
.github/workflows/aws-live-terraform-plan.yml
```

기본 실행:

```text
execute_live_plan=false
```

이 경우 AWS 인증 없이 execution plan artifact만 생성한다.

실제 plan 실행 조건:

```text
execute_live_plan=true
expected_aws_account_id=<12 digit account ID>
plan_stage=<one of five selectors>
allow_destructive=false
allow_optional_adapters=false
```

실제 plan job은:

1. protected environment 승인
2. GitHub OIDC role assumption
3. account/state backend 검증
4. 선택한 private tfvars decode
5. remote S3 backend init
6. `terraform validate`
7. saved `terraform plan`
8. ephemeral plan JSON 분석
9. sanitized evidence 생성
10. raw tfvars, binary plan, raw plan JSON 삭제

## 7. Plan risk gate

Parser:

```text
scripts/deploy/summarize-terraform-plan.py
```

기본 차단 항목:

- delete action
- create+delete replacement
- internet-facing ALB
- `0.0.0.0/0` 또는 `::/0` ingress
- publicly accessible RDS
- S3 public access block 완화
- EKS endpoint CIDR 전체 공개
- Bedrock/OpenSearch optional adapter resource

Cost-bearing resource는 별도 목록으로 표시한다.

- EKS cluster/node group
- RDS instance
- NAT Gateway
- ALB
- CloudFront distribution
- EC2 instance
- OpenSearch collection/domain

이 목록은 가격 계산 결과가 아니다. Apply 승인 전에는 AWS Pricing Calculator 또는 같은 기준의 비용 산출물로 월 비용 상한을 별도로 확인한다. 예상 비용이 승인된 상한을 넘으면 plan이 기술적으로 정상이어도 중단한다.

## 8. Sensitive evidence boundary

Terraform binary plan과 `terraform show -json` 결과에는 sensitive value가 포함될 수 있다. 따라서 workflow는 다음을 artifact로 업로드하지 않는다.

```text
live.tfplan
live-plan.json
live.auto.tfvars
backend.hcl
```

업로드하는 것은 다음뿐이다.

```text
caller-identity.json
state-lock-table-status.txt
tfvars.sha256
binary-plan.sha256
provider-lock.sha256
plan-risk-summary.txt
plan-risk-summary.json
plan-risk-summary.md
live-plan-summary.txt
```

즉 raw plan은 runner 내부에서만 사용하고 삭제한다. Evidence에는 resource address/type/action, 위험 카운트, digest만 남긴다.

## 9. 단계별 중단 기준

### Network

- public ingress 확대
- 예상하지 않은 NAT Gateway
- subnet/route replacement
- internal load balancer tag 제거

### Runtime dependencies

- S3 public access
- ECR repository replacement
- runtime Secret payload에 password 포함
- optional adapter용 OpenSearch/Bedrock resource 등장

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

## 10. Apply 승인 조건

현재 workflow는 apply를 수행하지 않는다. 향후 apply 작업은 다음 조건이 모두 충족된 뒤 별도 승인 단계로 진행한다.

1. 최신 source/runtime/package 자동 gate 통과
2. 최신 manual Runtime Contract Verification 통과
3. plan evidence의 destructive/public/optional-adapter count가 0
4. expected account/region 확인
5. state versioning 및 lock 확인
6. resource action과 월 비용 상한 검토
7. 단계별 rollback target 확인
8. 변경 창과 cleanup 책임자 확정
9. apply 명령과 plan digest를 별도로 검토

`allow_destructive=true`는 일반적인 apply 허용 스위치가 아니다. 데이터 이전·백업·복구 계획이 첨부된 별도 변경에서만 사용할 수 있다.

## 11. Rollback 원칙

- Network/EKS/RDS replacement는 일반 배포 rollback으로 처리하지 않는다.
- Backend는 이전 known-good image digest로 되돌린다.
- Kubernetes rollout은 이전 ReplicaSet으로 복구한다.
- Controller는 이전 Helm revision으로 rollback한다.
- Frontend는 이전 검증 build를 다시 sync하고 mutable entrypoint만 invalidate한다.
- DB migration은 애플리케이션 rollback과 분리한다. 검증되지 않은 down migration을 자동 실행하지 않는다.
- 장애 evidence를 수집하기 전에 리소스를 삭제하지 않는다.

## 12. 최종 live evidence

실제 운영 경험 포트폴리오로 인정하려면 다음 evidence가 필요하다.

- 각 Terraform stage plan digest와 sanitized risk summary
- apply 전후 output 차이
- ECR image digest와 Deployment digest 일치
- ExternalSecret sync와 9-key target Secret 확인
- internal ALB target health
- CloudFront VPC origin 상태
- authenticated browser E2E
- 401/403/404 JSON 보존
- API cache 비활성 확인
- controlled readiness 또는 dependency failure
- 계층별 원인 확인, 복구, 재검증 타임라인
- frontend/backend rollback evidence

Workflow 성공만으로 실제 운영 완료를 주장하지 않는다.
