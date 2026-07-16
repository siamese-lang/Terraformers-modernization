# Next Chat Handoff: Terraformers Live AWS Deployment

## 프로젝트 목표

원본 Terraformers 팀 프로젝트의 기능 흐름을 보존하면서 backend/RDB와 AWS 운영환경을 일관된 구조로 완성한다. 새 서비스를 만드는 작업이 아니며, 원본 저장소와 `siamese-lang/rdb-refactor`에서 재사용할 수 있는 도메인·서비스·운영 계약을 우선 재사용한다.

## 현재 기준선

- repository: `siamese-lang/Terraformers-modernization`
- baseline branch: `agent/rdb-domain-realignment`
- Draft PR: `#32`
- live AWS resource mutation: 아직 없음
- caller account inventory: expected account와 일치 확인
- static deployment contracts: 완료
- actual AWS integration/evidence: 다음 단계

## 반드시 먼저 읽을 파일

```text
config/live-deployment-stages.json
config/live-aws-prerequisites.json
docs/live-aws-predeployment-readiness.md
docs/live-aws-prerequisite-inventory.md
.github/workflows/aws-live-terraform-plan.yml
infra/terraform/bootstrap/aws-live-foundation/*
```

## 고정된 배포 기준

```text
Terraform              1.15.8
state                   versioned private S3
state locking           S3 native .tflock
DynamoDB locking        사용하지 않음
EKS                     1.35
EKS endpoint default    private
initial operator path   exact public /32 only
private node egress     single NAT gateway
public service entry    CloudFront only
optional adapters       disabled
```

## 다음 대화의 첫 작업

1. PR #32의 최신 head와 모든 automatic gate를 확인한다.
2. `pre-live-aws-readiness`와 static prerequisite inventory 결과를 확인한다.
3. AWS 계정에 `token.actions.githubusercontent.com` OIDC provider가 이미 존재하는지 읽기 전용으로 확인한다.
4. 실제 GitHub OIDC subject가 owner/name 형식인지 immutable owner/repository ID 형식인지 확인한다.
5. `infra/terraform/bootstrap/aws-live-foundation/terraform.tfvars.example`을 로컬 private tfvars로 복사하고 placeholder만 채운다.
6. bootstrap `terraform init -backend=false`, `validate`, `plan`까지만 수행한다.
7. plan의 S3 bucket, OIDC provider, plan role, IAM policy를 검토한다.
8. 사용자가 명시적으로 승인하기 전에는 bootstrap apply를 실행하지 않는다.

## bootstrap 이후 순서

```text
foundation apply approval
  -> bootstrap state migration
  -> aws-live-plan environment 생성
  -> GitHub variables/secrets 설정
  -> strict prerequisite inventory
  -> network plan only
```

network plan을 검토하기 전에는 runtime, RDS, EKS를 생성하지 않는다.

## 절대 자동 실행하지 않을 작업

- Terraform apply/destroy
- kubectl apply
- Helm install/upgrade
- Docker/ECR image push
- AWS resource mutation
- GitHub PR merge 또는 ready 전환
- External Secrets 설치
- public ALB/Ingress 추가
- Bedrock/OpenSearch/optional S3 writer/SQS adapter 활성화
- Secret 값 출력 또는 raw plan 업로드

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
