# Live AWS Prerequisite Inventory

## 목적

실제 Terraform plan 전에 다음 준비 상태를 읽기 전용으로 확인한다.

- 다섯 Terraform 환경의 필수 변수와 선행 output 연결
- GitHub protected environment `aws-live-plan` 존재 여부
- 필요한 GitHub variable·secret 이름의 등록 여부
- 로컬 AWS caller identity
- Terraform state S3 bucket 접근 및 versioning
- DynamoDB state lock table 상태

이 검사는 AWS 리소스를 생성·수정·삭제하지 않는다. Secret 값은 읽거나 출력하지 않고 이름의 존재 여부만 확인한다.

## 단계 입력 계약

Canonical contract:

```text
config/live-aws-prerequisites.json
```

정적 검사기는 각 `variables.tf`에서 default가 없는 변수를 추출하고 계약 파일과 비교한다. 또한 선행 Terraform 환경의 `outputs.tf`에 다음 단계가 요구하는 output이 실제로 존재하는지 확인한다.

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

`frontend-delivery`는 controller가 internal ALB를 실제로 생성하고 ARN이 확인된 뒤에만 계획할 수 있다.

## 검사 도구

```text
scripts/deploy/live-aws-prerequisite-inventory.py
```

출력:

```text
artifacts/live-aws-prerequisite-inventory/prerequisite-summary.txt
artifacts/live-aws-prerequisite-inventory/prerequisite-inventory.json
```

`artifacts/`는 Git에서 제외된다.

## 1. 정적 계약만 검사

AWS CLI와 GitHub 설정을 확인하지 않는다.

```powershell
python scripts/deploy/live-aws-prerequisite-inventory.py `
  --static-only `
  --fail-on-missing
```

정상 기준:

```text
live_aws_prerequisite_inventory=passed
static_contract=passed
terraform_stage_count=5
github_status=skipped-static-only
aws_status=skipped-static-only
secret_values_read=false
aws_mutation=none
```

## 2. GitHub 설정만 검사

AWS state가 아직 준비되지 않았다면 `--skip-aws`를 사용한다.

```powershell
python scripts/deploy/live-aws-prerequisite-inventory.py `
  --skip-aws
```

확인 대상 variable:

```text
AWS_REGION
AWS_TERRAFORM_STATE_BUCKET
AWS_TERRAFORM_LOCK_TABLE
AWS_TERRAFORM_STATE_PREFIX
```

확인 대상 secret:

```text
AWS_ROLE_TO_ASSUME
AWS_LIVE_NETWORK_TFVARS_B64
AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64
AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64
AWS_LIVE_EKS_TFVARS_B64
AWS_LIVE_FRONTEND_TFVARS_B64
```

검사기는 repository와 `aws-live-plan` environment에 등록된 이름을 합쳐 확인한다. Secret 값은 GitHub API로 읽지 않는다.

## 3. GitHub와 AWS state를 함께 검사

AWS CLI가 의도한 계정으로 인증된 상태에서 실행한다.

```powershell
python scripts/deploy/live-aws-prerequisite-inventory.py
```

의도한 계정 ID를 명시해 계정 혼동을 차단하려면 다음과 같이 실행한다.

```powershell
$ExpectedAccountId = "<12-digit-account-id>"

python scripts/deploy/live-aws-prerequisite-inventory.py `
  --expected-account-id $ExpectedAccountId
```

검사 항목:

```text
aws sts get-caller-identity
aws s3api head-bucket
aws s3api get-bucket-versioning
aws dynamodb describe-table
```

정상 기준:

```text
github_status=ready
missing_github_variable_count=0
missing_github_secret_count=0
aws_status=ready
secret_values_read=false
aws_mutation=none
```

## 4. 구성 완료 후 엄격 검사

모든 prerequisite를 설정한 뒤에는 누락 시 non-zero exit code를 반환하도록 한다.

```powershell
python scripts/deploy/live-aws-prerequisite-inventory.py `
  --expected-account-id $ExpectedAccountId `
  --fail-on-missing
```

## 결과 해석

### `github-environment-missing:aws-live-plan`

GitHub repository Settings에서 protected environment가 아직 생성되지 않았다. 이 inventory는 environment를 자동 생성하지 않는다.

### `github-variable-missing:<NAME>`

필요한 repository 또는 environment variable 이름이 없다.

### `github-secret-missing:<NAME>`

필요한 repository 또는 environment secret 이름이 없다. 검사 결과에는 Secret 값이 포함되지 않는다.

### `state-bucket-inaccessible`

설정된 state bucket이 없거나 현재 AWS identity에 읽기 권한이 없다.

### `state-bucket-versioning-not-enabled`

state bucket은 존재하지만 versioning이 `Enabled`가 아니다.

### `state-lock-table-not-active`

DynamoDB lock table이 없거나 `ACTIVE` 상태가 아니다.

### `source-output-missing:<stage>:<source>`

Terraform 단계 사이의 output/input 연결이 끊겼다. 실제 ARN이나 ID를 수동으로 조립하지 말고 선행 환경 output 계약을 수정해야 한다.

## 아직 별도로 확인할 항목

`AWS_ROLE_TO_ASSUME`의 값과 IAM trust policy는 Secret 목록 API로 확인할 수 없다. 따라서 이 inventory에서는 OIDC role trust를 `deferred-to-dedicated-check`로 기록한다.

다음 단계에서 role ARN을 명시적으로 확인한 뒤 다음 조건을 별도 검증한다.

```text
OIDC provider: token.actions.githubusercontent.com
audience: sts.amazonaws.com
subject: repo:siamese-lang/Terraformers-modernization:environment:aws-live-plan
```

이 trust 검증이 끝나기 전에는 live Terraform plan을 실행하지 않는다.
