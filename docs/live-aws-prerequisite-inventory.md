# Live AWS Prerequisite Inventory

## 목적

실제 Terraform plan 전에 다음 준비 상태를 읽기 전용으로 확인한다.

- 다섯 Terraform 환경의 필수 변수와 선행 output 연결
- GitHub protected environment `aws-live-plan` 존재 여부
- 필요한 GitHub variable·secret 이름의 등록 여부
- 로컬 AWS caller identity와 예상 계정 일치
- Terraform state S3 bucket 접근 및 versioning
- GitHub OIDC plan role의 provider, audience, environment subject

이 검사는 AWS 리소스를 생성·수정·삭제하지 않는다. private tfvars Secret 값은 읽거나 출력하지 않고 이름의 존재 여부만 확인한다.

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

DynamoDB locking은 사용하지 않는다. 각 stage state는 다음 경로와 같은 S3 object와 `.tflock` object를 사용한다.

```text
<state-prefix>/<stage>/terraform.tfstate
<state-prefix>/<stage>/terraform.tfstate.tflock
```

## 단계 입력 계약

주요 handoff:

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

`frontend-delivery`는 controller가 internal ALB를 실제로 생성하고 ARN과 target health가 확인된 뒤에만 계획한다.

## 검사 도구

```text
scripts/deploy/live-aws-prerequisite-inventory.py
```

출력:

```text
artifacts/live-aws-prerequisite-inventory/prerequisite-summary.txt
artifacts/live-aws-prerequisite-inventory/prerequisite-inventory.json
```

`artifacts/`는 Git에서 제외된다. 실행을 시작할 때 이전 summary와 JSON은 삭제되므로 중단된 실행의 오래된 결과를 새 결과로 오해하지 않는다.

## 1. 정적 계약만 검사

```powershell
python scripts/deploy/live-aws-prerequisite-inventory.py `
  --static-only `
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

## 2. GitHub 설정만 검사

AWS foundation을 아직 생성하지 않았다면 다음처럼 실행한다.

```powershell
python scripts/deploy/live-aws-prerequisite-inventory.py --skip-aws
```

Environment 또는 repository variable:

```text
AWS_REGION
AWS_ROLE_TO_ASSUME
AWS_TERRAFORM_STATE_BUCKET
AWS_TERRAFORM_STATE_PREFIX
```

`AWS_ROLE_TO_ASSUME`은 credential이 아니라 role ARN이므로 Secret이 아닌 protected environment variable로 관리한다.

Environment Secret:

```text
AWS_LIVE_NETWORK_TFVARS_B64
AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64
AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64
AWS_LIVE_EKS_TFVARS_B64
AWS_LIVE_FRONTEND_TFVARS_B64
```

검사기는 repository와 `aws-live-plan` environment에 등록된 이름을 합쳐 확인한다. Secret 값은 GitHub API로 읽지 않는다.

## 3. GitHub와 AWS foundation 함께 검사

```powershell
$ExpectedAccountId = "<12-digit-account-id>"

python scripts/deploy/live-aws-prerequisite-inventory.py `
  --expected-account-id $ExpectedAccountId
```

읽기 전용 검사:

```text
aws sts get-caller-identity
aws s3api head-bucket
aws s3api get-bucket-versioning
aws iam get-role
```

OIDC role trust 정상 조건:

```text
provider: arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com
audience: sts.amazonaws.com
subject: repo:siamese-lang/Terraformers-modernization:environment:aws-live-plan
wildcard subject: 없음
```

정상 기준:

```text
github_status=ready
missing_github_variable_count=0
missing_github_secret_count=0
aws_status=ready
oidc_role_trust_status=ready
secret_values_read=false
aws_mutation=none
```

## 4. 구성 완료 후 엄격 검사

```powershell
python scripts/deploy/live-aws-prerequisite-inventory.py `
  --expected-account-id $ExpectedAccountId `
  --fail-on-missing
```

## 결과 해석

- `github-environment-missing:aws-live-plan`: protected environment가 없다.
- `github-variable-missing:<NAME>`: 필요한 environment 또는 repository variable이 없다.
- `github-secret-missing:<NAME>`: 필요한 private tfvars Secret 이름이 없다.
- `state-bucket-inaccessible`: state bucket이 없거나 현재 identity가 접근할 수 없다.
- `state-bucket-versioning-not-enabled`: versioning이 `Enabled`가 아니다.
- `oidc-role-arn-invalid`: `AWS_ROLE_TO_ASSUME`이 IAM role ARN 형식이 아니다.
- `oidc-role-unavailable`: 현재 AWS identity가 role을 조회할 수 없거나 role이 없다.
- `oidc-role-trust-mismatch`: provider, audience 또는 exact environment subject가 계약과 다르다.
- `source-output-missing:<stage>:<source>`: Terraform 단계 output/input 연결이 끊겼다.

AWS foundation 생성 전에는 `incomplete`가 정상이다. 이 결과를 우회해서 local credential로 live stage를 apply하지 않는다.
