# Live AWS Predeployment Readiness

## 확정된 배포 기준

```text
Terraform CLI                       1.15.8
Terraform state                     private versioned S3
Terraform state locking             S3 native .tflock
GitHub authentication               protected environment + OIDC
EKS Kubernetes                      1.35
EKS endpoint default                private
Initial operator access             temporary public endpoint + exact operator /32 only
Private subnet egress               one NAT gateway for short-lived validation
AWS Load Balancer Controller        3.4.2
External Secrets Operator chart     2.7.0
Public service entry                CloudFront only
Optional adapters                   disabled
```

Source contracts:

```text
config/live-aws-prerequisites.json
config/live-kubernetes-addons.json
```

Detailed procedures:

```text
docs/live-foundation-state-migration.md
docs/live-aws-prerequisite-inventory.md
docs/live-kubernetes-addons.md
docs/live-stage-tfvars-handoff.md
```

이 기준을 바꾸려면 live plan 전에 PR에서 계약과 evidence를 함께 수정한다.

## 현재 완료 상태

2026-07-17 기준:

```text
AWS foundation apply                complete
bootstrap managed resources         9
bootstrap state backend             S3
bootstrap state version             1
state payload                       semantically equivalent
post-migration plan                 no changes
provider schema                     verified in isolated TF_DATA_DIR
network/runtime/RDS/EKS apply        not started
GitHub environment mutation         not started
```

Foundation migration 상세 evidence는 `docs/live-foundation-state-migration.md`에 기록한다.

## Agent Toolkit for AWS 사용 위치

Agent Toolkit for AWS는 실제 배포 이후 다음 읽기 작업에 보조적으로 사용할 수 있다.

- EKS, RDS, ALB, CloudFront 상태 조회
- CloudWatch 로그와 지표 조사
- 배포 실패 원인 후보 정리
- 비용 증가 원인 조사
- 최신 AWS 문서와 troubleshooting procedure 조회

필수 배포 도구는 아니다. Terraform state, GitHub OIDC, protected environment, private tfvars, 승인 절차를 대신하지 않는다.

초기 사용 원칙:

```text
agent IAM access       read-only
agent write operation  금지
terraform apply        인간이 검토한 terminal에서만
kubectl/helm mutation  인간이 검토한 terminal에서만
CloudTrail/CloudWatch  agent action audit 활성화
```

## 1. 자동 사전 검증

```powershell
python scripts/checks/pre-live-aws-readiness-verification.py
python scripts/checks/live-stage-tfvars-builder-verification.py

python scripts/deploy/live-aws-prerequisite-inventory.py `
  --static-only `
  --fail-on-missing
```

정상 기준:

```text
pre_live_aws_readiness=passed
terraform_cli_version=1.15.8
state_locking=s3-native-lockfile
eks_default_version=1.35
eks_endpoint_default=private
live_egress_baseline=single-nat-gateway
load_balancer_controller_version=3.4.2
external_secrets_version=2.7.0
tfvars_example_count=5
generated_handoff_stage_count=3
deprecated_dynamodb_locking=false
optional_adapters_enabled=false
aws_authentication=none
aws_mutation=none
```

## 2. AWS foundation bootstrap — 완료

코드:

```text
infra/terraform/bootstrap/aws-live-foundation
```

생성·검증 완료 대상:

- versioning이 활성화된 private S3 state bucket
- public access block과 TLS-only bucket policy
- S3 native state lockfile 권한
- 기존 GitHub Actions IAM OIDC provider 재사용
- `aws-live-plan` environment subject만 신뢰하는 plan role
- AWS `ReadOnlyAccess`와 state/lock object에 한정한 write 권한

완료 evidence:

```text
ManagedStateResourceCount=9
StateResourcesExact=true
StateOutputsExact=true
StateCheckStatuses=pass
StatePayloadSemanticallyEquivalent=true
PostMigrationPlanNoChanges=true
StaleLockObjectPresent=false
LocalStateBackupPreserved=true
```

Bootstrap state와 private backup 원문은 저장소 또는 GitHub artifact에 업로드하지 않는다. State bucket과 bootstrap role은 다른 live resource cleanup 과정에서 임의 삭제하지 않는다.

## 3. GitHub protected environment — 다음 단계

다음 environment를 생성한다.

```text
aws-live-plan
```

권장 protection:

- deployment branch: `main`만 허용
- required reviewer 설정
- administrator bypass 비활성 또는 사용 금지
- environment variable과 Secret은 environment scope에 저장

Environment variable:

```text
AWS_REGION
AWS_ROLE_TO_ASSUME
AWS_TERRAFORM_STATE_BUCKET
AWS_TERRAFORM_STATE_PREFIX
```

Environment Secret:

```text
AWS_LIVE_NETWORK_TFVARS_B64
AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64
AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64
AWS_LIVE_EKS_TFVARS_B64
AWS_LIVE_FRONTEND_TFVARS_B64
```

Role ARN은 credential이 아니므로 Secret이 아니라 variable로 저장한다. GitHub 설정 mutation은 누락 목록을 확인하고 별도 승인한 뒤 수행한다.

## 4. Private tfvars 준비

검토용 예시:

```text
infra/terraform/envs/aws-runtime-network/live.tfvars.example
infra/terraform/envs/backend-runtime-dependencies/live.tfvars.example
infra/terraform/envs/backend-stateful-dependencies/live.tfvars.example
infra/terraform/envs/eks-runtime/live.tfvars.example
infra/terraform/envs/frontend-delivery/live.tfvars.example
```

실제 파일은 `.tfvars`로 복사하며 Git에서 제외한다. Network와 runtime-dependencies는 operator input으로 작성한다. Applied output이 필요한 나머지 stage는 다음 generator를 사용한다.

```text
scripts/deploy/build-live-stage-tfvars.py
```

Generator handoff:

```text
network -> stateful-dependencies
network + runtime-dependencies + operator /32 -> eks-runtime
verified internal ALB ARN -> frontend-delivery
```

각 파일의 placeholder를 실제 output으로 교체한 뒤 plan을 검토한다. 예시 파일 자체를 수정하지 않는다.

Secret용 base64 생성 예:

```powershell
$Path = "infra\terraform\envs\aws-runtime-network\live.tfvars"
$Encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))

gh secret set AWS_LIVE_NETWORK_TFVARS_B64 `
  --repo siamese-lang/Terraformers-modernization `
  --env aws-live-plan `
  --body $Encoded
```

다른 네 stage도 같은 방식으로 등록한다. plaintext와 base64 값을 console output, workflow artifact, issue, PR에 붙이지 않는다.

## 5. Strict prerequisite inventory

GitHub environment/variable/Secret 설정 후 실행한다.

```powershell
$ExpectedAccountId = "<12-digit-account-id>"

python scripts/deploy/live-aws-prerequisite-inventory.py `
  --expected-account-id $ExpectedAccountId `
  --fail-on-missing
```

성공 조건:

```text
github_status=ready
missing_github_variable_count=0
missing_github_secret_count=0
aws_status=ready
oidc_role_trust_status=ready
secret_values_read=false
aws_mutation=none
```

Strict inventory를 우회해 local static credential로 live stage를 apply하지 않는다.

## 6. EKS operator access와 egress

Terraform module 기본값은 private endpoint다.

초기 설치 시 local operator가 controller와 External Secrets를 설치해야 하므로 live EKS tfvars에서는 다음을 명시한다.

```text
cluster_endpoint_public_access = true
cluster_endpoint_public_access_cidrs = ["<current-public-ip>/32"]
```

금지:

```text
0.0.0.0/0
::/0
GitHub-hosted runner 전체 IP 대역 허용
```

초기 private node egress는 single NAT gateway를 사용한다. Endpoint-only 최적화는 첫 성공 evidence 이후 별도 계획으로 수행한다.

## 7. Kubernetes add-on 설치 경계

Pinned versions:

```text
AWS Load Balancer Controller  3.4.2
External Secrets Operator     2.7.0
```

External Secrets identity는 분리한다.

```text
controller ServiceAccount     external-secrets/external-secrets
provider-auth ServiceAccount  terraformers-runtime/terraformers-external-secrets
```

External Secrets CRD는 pinned v2.7.0 bundle을 server-side apply하고 Helm에는 `installCRDs=false`를 설정한다. 모든 kubectl/Helm 작업은 별도 승인 후 수행한다.

## 8. 실제 실행 순서

```text
A. AWS foundation plan/apply                         완료
B. bootstrap state migrate/reconciliation            완료
C. GitHub environment/variables/secrets 설정          다음 단계
D. prerequisite strict inventory
E. network live plan
F. network apply 승인
G. runtime-dependencies plan/apply
H. stateful-dependencies plan/apply
I. eks-runtime plan/apply
J. image publish
K. pinned controller/External Secrets 설치
L. backend rollout 및 internal ALB 확인
M. frontend-delivery plan/apply
N. frontend publish
O. E2E, failure/recovery, rollback evidence
P. cleanup 또는 유지 결정
```

각 단계는 이전 단계 output과 evidence를 확인한 뒤 진행한다.

## 9. 비용·중단·정리 기준

비용 발생 핵심 자원:

```text
EKS control plane
EC2 managed node
NAT gateway and processed data
RDS MariaDB and storage
internal ALB
CloudFront and S3 requests
public IPv4 where applicable
CloudWatch logs
```

Apply 전 반드시 기록:

```text
maximum validation window
maximum expected spend
resource owner
cleanup date
state bucket retention owner
rollback image digest
RDS snapshot decision
```

중단 조건:

- 예상 계정 불일치
- plan에 delete/replace 포함
- public RDS 또는 public ALB
- world-open ingress
- EKS 1.35 이외의 미검토 버전
- NAT gateway가 두 개 이상 생성됨
- unpinned Helm chart
- External Secrets controller/provider identity 공유
- optional Bedrock/OpenSearch adapter 활성화
- 실제 tfvars 또는 raw plan/state가 artifact에 포함됨

Cleanup은 application traffic부터 역순으로 수행한다. State bucket과 bootstrap role은 다른 live resource와 함께 임의 삭제하지 않는다.
