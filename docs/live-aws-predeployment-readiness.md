# Live AWS Predeployment Readiness

## 오늘 확정한 배포 기준

실제 AWS 생성 전 저장소 기준을 다음으로 고정한다.

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
docs/live-kubernetes-addons.md
docs/live-stage-tfvars-handoff.md
```

이 기준을 바꾸려면 live plan 전에 PR에서 계약과 evidence를 함께 수정한다.

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

현재 웹 대화에 도구가 자동 연결되는 것은 아니다. Codex CLI, Claude Code, Kiro 또는 MCP-compatible 환경에 별도로 설치하고 전용 read-only identity를 연결한 경우에만 사용한다.

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

## 2. AWS foundation bootstrap

코드:

```text
infra/terraform/bootstrap/aws-live-foundation
```

생성 대상:

- versioning이 활성화된 private S3 state bucket
- public access block과 TLS-only bucket policy
- S3 native state lockfile 권한
- GitHub Actions IAM OIDC provider 또는 기존 provider 재사용
- `aws-live-plan` environment subject만 신뢰하는 plan role
- AWS `ReadOnlyAccess`와 state/lock object에 한정한 write 권한

주의:

- bootstrap 자체는 최초 1회 local state로 시작한다.
- bucket과 role plan을 먼저 검토하고 명시적으로 승인한 뒤 apply한다.
- apply 성공 후 `backend.hcl.example`을 복사·수정하고 bootstrap state를 생성된 S3 backend로 migrate한다.
- state bucket에는 `prevent_destroy=true`가 적용되어 있다.
- AWS 계정에 GitHub OIDC provider가 이미 있으면 `existing_github_oidc_provider_arn`을 설정해 중복 생성을 막는다.
- GitHub immutable OIDC subject를 사용하도록 전환한 저장소라면 실제 subject를 확인한 뒤 `github_oidc_subjects`를 교체한다.

오늘은 bootstrap plan/apply를 실행하지 않는다.

## 3. GitHub protected environment

AWS foundation output이 확정된 뒤에 다음 environment를 생성한다.

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

Role ARN은 credential이 아니므로 Secret이 아니라 variable로 저장한다.

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

## 5. EKS operator access와 egress

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

초기 private node egress는 single NAT gateway를 사용한다. 이유는 EKS bootstrap 과정에서 ECR, STS, EKS, CloudWatch 등 여러 AWS endpoint와 외부 package source가 필요하기 때문이다. endpoint-only 최적화는 첫 성공 evidence 이후 별도 계획으로 수행한다.

## 6. Kubernetes add-on 설치 경계

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

## 7. 실제 실행 순서

다음 대화에서는 한꺼번에 생성하지 않는다.

```text
A. AWS foundation plan
B. foundation plan 검토와 명시적 apply 승인
C. state migrate
D. GitHub environment/variables/secrets 설정
E. prerequisite strict inventory
F. network live plan
G. network apply 승인
H. runtime-dependencies plan/apply
I. stateful-dependencies plan/apply
J. eks-runtime plan/apply
K. image publish
L. pinned controller/External Secrets 설치
M. backend rollout 및 internal ALB 확인
N. frontend-delivery plan/apply
O. frontend publish
P. E2E, failure/recovery, rollback evidence
Q. cleanup 또는 유지 결정
```

각 단계는 이전 단계 output과 evidence를 확인한 뒤 진행한다.

## 8. 비용·중단·정리 기준

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

apply 전 반드시 기록:

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
- 실제 tfvars 또는 raw plan이 artifact에 포함됨

cleanup은 application traffic부터 역순으로 수행한다. state bucket과 bootstrap role은 다른 live resource와 함께 임의 삭제하지 않는다.
