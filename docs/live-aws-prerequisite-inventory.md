# Live AWS Prerequisite Inventory

## 목적

실제 Terraform plan 전에 현재 stage에 필요한 준비 상태만 읽기 전용으로 확인한다.

- 다섯 Terraform stage의 필수 변수와 선행 output 계약
- GitHub protected environment `aws-live-plan`
- 공통 GitHub variable 4개
- 선택한 stage의 private tfvars Secret 이름
- 로컬 AWS caller identity와 예상 계정 일치
- Terraform state S3 bucket 접근 및 versioning
- GitHub OIDC plan role의 provider, audience, environment subject

이 검사는 AWS 또는 GitHub 설정을 생성·수정·삭제하지 않는다. Secret 값은 읽거나 출력하지 않고 이름의 존재 여부만 확인한다.

AWS foundation apply와 bootstrap state migration은 완료됐다.

```text
docs/live-foundation-state-migration.md
```

## 기준 계약

```text
config/live-aws-prerequisites.json
```

고정 기준:

```text
Terraform CLI: 1.15.8
state locking: S3 native lockfile
GitHub environment: aws-live-plan
OIDC subject: repo:siamese-lang/Terraformers-modernization:environment:aws-live-plan
```

DynamoDB locking은 사용하지 않는다.

```text
<state-prefix>/<stage>/terraform.tfstate
<state-prefix>/<stage>/terraform.tfstate.tflock
```

Bootstrap canonical state:

```text
<state-prefix>/bootstrap/terraform.tfstate
```

## Stage별 Secret 계약

처음부터 다섯 Secret을 모두 요구하지 않는다. 해당 stage를 계획할 수 있는 시점에 그 stage의 Secret만 등록한다.

```text
network
  AWS_LIVE_NETWORK_TFVARS_B64

runtime-dependencies
  AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64

stateful-dependencies
  AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64
  prerequisite: applied network outputs

eks-runtime
  AWS_LIVE_EKS_TFVARS_B64
  prerequisite: applied network and runtime-dependencies outputs

frontend-delivery
  AWS_LIVE_FRONTEND_TFVARS_B64
  prerequisite: verified internal ALB ARN
```

공통 GitHub variable은 모든 stage에서 동일하다.

```text
AWS_REGION
AWS_ROLE_TO_ASSUME
AWS_TERRAFORM_STATE_BUCKET
AWS_TERRAFORM_STATE_PREFIX
```

`AWS_ROLE_TO_ASSUME`은 credential이 아니라 role ARN이므로 Secret이 아닌 protected environment variable로 관리한다.

## 단계 입력 계약

```text
network
  -> vpc_id
  -> vpc_cidr_block
  -> private_subnet_ids
  -> private_subnet_cidr_blocks

runtime-dependencies
  -> upload_bucket_arn
  -> result_bucket_arn
  -> ai_log_queue_arn
  -> terraform_log_queue_arn
  -> backend_runtime_secret_arn

live private origin
  -> api_origin_load_balancer_arn
```

`stateful-dependencies`와 `eks-runtime` tfvars는 선행 state output을 받아 generator로 만든다.

```text
scripts/deploy/build-live-stage-tfvars.py
```

`frontend-delivery`는 controller가 internal ALB를 생성하고 ARN과 target health가 확인된 뒤에만 준비한다.

## 검사 도구

Git Bash 진입점:

```text
scripts/deploy/inventory-live-aws-prerequisites.sh
```

Python inventory 본체:

```text
scripts/deploy/live-aws-prerequisite-inventory.py
```

출력:

```text
artifacts/live-aws-prerequisite-inventory/prerequisite-summary.txt
artifacts/live-aws-prerequisite-inventory/prerequisite-inventory.json
```

`artifacts/`는 Git에서 제외된다. 이전 summary와 JSON은 실행 시작 시 삭제된다.

## 1. 정적 계약 검사

```bash
py -3 scripts/deploy/live-aws-prerequisite-inventory.py \
  --static-only \
  --fail-on-missing
```

정상 기준:

```text
live_aws_prerequisite_inventory=passed
static_contract=passed
terraform_cli_version=1.15.8
state_locking=s3-native-lockfile
terraform_stage_count=5
github_status=skipped-static-only
aws_status=skipped-static-only
secret_values_read=false
aws_mutation=none
```

## 2. 현재 stage inventory

기본 stage는 `network`다.

```bash
bash scripts/deploy/inventory-live-aws-prerequisites.sh \
  --expected-head "$EXPECTED_HEAD"
```

명시적으로 지정할 수도 있다.

```bash
bash scripts/deploy/inventory-live-aws-prerequisites.sh \
  --expected-head "$EXPECTED_HEAD" \
  --stage network
```

지원 stage:

```text
network
runtime-dependencies
stateful-dependencies
eks-runtime
frontend-delivery
all
```

`all`은 전체 배포 준비 상태를 최종 감사할 때만 사용한다. 최초 network plan의 선행 조건으로 사용하지 않는다.

## 3. 엄격 검사

GitHub environment, 공통 variable, 현재 stage Secret과 AWS foundation 연결이 모두 준비된 뒤 실행한다.

```bash
bash scripts/deploy/inventory-live-aws-prerequisites.sh \
  --expected-head "$EXPECTED_HEAD" \
  --stage network \
  --strict
```

Network 정상 기준:

```text
live_aws_prerequisite_inventory=passed
github_status=ready
missing_github_variable_count=0
missing_github_secret_count=0
aws_status=ready
oidc_role_trust_status=ready
InventoryStage=network
StrictMode=true
SecretValuesRead=false
AwsMutation=none
```

## 결과 해석

- `github-environment-missing:aws-live-plan`: protected environment가 없다.
- `github-variable-missing:<NAME>`: 공통 environment 또는 repository variable이 없다.
- `github-secret-missing:<NAME>`: 선택한 stage의 private tfvars Secret 이름이 없다.
- `state-bucket-inaccessible`: state bucket variable이 설정된 뒤에도 현재 identity가 bucket을 조회하지 못한다.
- `state-bucket-versioning-not-enabled`: versioning이 `Enabled`가 아니다.
- `oidc-role-arn-invalid`: `AWS_ROLE_TO_ASSUME`이 IAM role ARN 형식이 아니다.
- `oidc-role-unavailable`: 현재 AWS identity가 role을 조회할 수 없거나 role이 없다.
- `oidc-role-trust-mismatch`: provider, audience 또는 exact environment subject가 계약과 다르다.
- `source-output-missing:<stage>:<source>`: Terraform 단계 output/input 계약이 끊겼다.

GitHub variable이 아직 등록되지 않은 inventory에서는 bucket과 role을 해석할 수 없어 AWS status도 `incomplete`가 된다. 이는 foundation 손상을 뜻하지 않는다.

누락 항목을 placeholder Secret이나 임의 output으로 우회하지 않는다. 현재 stage 준비가 끝난 뒤 다음 stage로 진행한다.
