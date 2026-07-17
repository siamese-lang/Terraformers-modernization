# Next Chat Handoff: Terraformers Live AWS Deployment

## 프로젝트 목표

원본 Terraformers 팀 프로젝트의 기능 흐름을 보존하면서 backend/RDB와 AWS 운영환경을 일관된 구조로 완성한다. 새 서비스를 만드는 작업이 아니며, 원본 저장소와 `siamese-lang/rdb-refactor`에서 재사용할 수 있는 도메인·서비스·운영 계약을 우선 재사용한다.

## 현재 기준선

- repository: `siamese-lang/Terraformers-modernization`
- baseline branch: `agent/rdb-domain-realignment`
- Draft PR: `#32`
- AWS foundation apply: 완료
- bootstrap managed resources: 9개
- bootstrap canonical state: versioned private S3
- state locking: S3 native `.tflock`
- state migration reconciliation: 완료
- final reconciled head: `f70f157deccacd721f4c6864f6dd91add120c00f`
- network/runtime/RDS/EKS apply: 아직 없음
- GitHub environment/variables/secrets mutation: 아직 없음

Foundation state evidence:

```text
RemoteStateVersionCount=1
ManagedStateResourceCount=9
StateResourcesExact=true
StateOutputsExact=true
StateCheckResultsOrderOnly=true
StateCheckStatuses=pass
StatePayloadSemanticallyEquivalent=true
StateLineageRebased=true
StateSerialResetValid=true
PostMigrationPlanNoChanges=true
StaleLockObjectPresent=false
LocalStateBackupPreserved=true
ProviderRuntimeIsolation=success
ProviderSchemaLoaded=true
RemoteStateWriteAttempted=false
```

상세 기록:

```text
docs/live-foundation-state-migration.md
```

## 반드시 먼저 읽을 파일

```text
config/live-deployment-stages.json
config/live-aws-prerequisites.json
config/live-kubernetes-addons.json
docs/live-foundation-state-migration.md
docs/live-aws-predeployment-readiness.md
docs/live-aws-prerequisite-inventory.md
docs/live-kubernetes-addons.md
docs/live-stage-tfvars-handoff.md
.github/workflows/aws-live-terraform-plan.yml
infra/terraform/bootstrap/aws-live-foundation/*
```

## 고정된 배포 기준

```text
Terraform                         1.15.8
state                             versioned private S3
state locking                     S3 native .tflock
DynamoDB locking                  사용하지 않음
EKS                               1.35
EKS endpoint default              private
initial operator path             exact public /32 only
private node egress               single NAT gateway
AWS Load Balancer Controller      3.4.2
External Secrets Operator chart   2.7.0
public service entry              CloudFront only
optional adapters                 disabled
```

External Secrets identity boundary:

```text
controller ServiceAccount     external-secrets/external-secrets
provider-auth ServiceAccount  terraformers-runtime/terraformers-external-secrets
```

두 ServiceAccount를 합치거나 controller 전체에 Terraformers Secrets Manager IRSA role을 부여하지 않는다.

## 다음 대화의 첫 작업

1. PR #32의 최신 head와 automatic gate를 확인한다.
2. `aws-live-plan` protected environment 존재 여부를 읽기 전용으로 확인한다.
3. 다음 environment variable 이름의 등록 여부를 확인한다.

```text
AWS_REGION
AWS_ROLE_TO_ASSUME
AWS_TERRAFORM_STATE_BUCKET
AWS_TERRAFORM_STATE_PREFIX
```

4. 다음 environment Secret 이름의 등록 여부를 확인한다. 값은 읽거나 출력하지 않는다.

```text
AWS_LIVE_NETWORK_TFVARS_B64
AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64
AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64
AWS_LIVE_EKS_TFVARS_B64
AWS_LIVE_FRONTEND_TFVARS_B64
```

5. 누락 항목을 확인한 뒤 별도 승인하에 GitHub environment/variable/Secret을 설정한다.
6. `scripts/deploy/live-aws-prerequisite-inventory.py --expected-account-id <id> --fail-on-missing`을 통과시킨다.
7. Network private tfvars와 state backend key만 검토한다.
8. `network` plan만 생성하고 delete/replace/public exposure/NAT count를 검토한다.
9. 별도 명시적 승인 전에는 network apply를 실행하지 않는다.

## 이후 순서

```text
aws-live-plan environment 생성
  -> GitHub variables/secrets 설정
  -> strict prerequisite inventory
  -> network plan only
  -> network apply approval
  -> runtime-dependencies plan/apply
  -> stateful-dependencies plan/apply
  -> eks-runtime plan/apply
```

Network plan을 검토하기 전에는 runtime, RDS, EKS를 생성하지 않는다.

Applied output을 다음 단계 tfvars로 넘길 때는 수동 조립보다 다음 generator를 우선 사용한다.

```text
scripts/deploy/build-live-stage-tfvars.py
```

지원 handoff:

```text
network -> stateful-dependencies
network + runtime-dependencies + operator /32 -> eks-runtime
verified internal ALB ARN -> frontend-delivery
```

## 절대 자동 실행하지 않을 작업

- Terraform apply/destroy
- kubectl apply
- Helm install/upgrade
- Docker/ECR image push
- GitHub environment/variable/Secret mutation
- GitHub PR merge 또는 ready 전환
- External Secrets 설치
- public ALB/Ingress 추가
- Bedrock/OpenSearch/optional S3 writer/SQS adapter 활성화
- Secret 값 출력 또는 raw plan/state 업로드

각 mutation은 대상과 범위를 명시한 별도 승인 이후에만 수행한다.

## Agent Toolkit for AWS

실제 AWS 생성 후 읽기 전용 진단 보조 도구로만 검토한다. CloudWatch 로그·지표, EKS/RDS/ALB 상태, 비용 이상 조사에 사용할 수 있으나 Terraform state/OIDC/승인 절차를 대체하지 않는다. 초기 agent identity에는 write permission을 부여하지 않는다.

## 프로젝트 완료 기준

다음이 모두 있어야 프로젝트를 완료로 판단한다.

- stage별 reviewed plan과 apply evidence
- immutable backend image digest
- healthy EKS nodes, controllers, External Secrets, backend Pods
- private internal ALB와 CloudFront VPC origin
- private frontend S3/OAC
- 로그인, 업로드, 프로젝트/파일 등록, 분석, Terraform 조회 E2E
- public project read 및 401/403/404 JSON contract
- controlled failure 1개와 layer-specific diagnosis
- recovery와 rollback evidence
- 비용 기록과 cleanup/retention 결정
- README와 portfolio document 최종 정리
