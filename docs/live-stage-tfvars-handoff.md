# Live Stage tfvars Handoff

## 목적

Terraform stage 사이의 ID, CIDR, ARN을 사람이 반복해서 복사하면서 발생하는 오류를 줄인다.

Generator:

```text
scripts/deploy/build-live-stage-tfvars.py
```

지원 대상:

```text
network outputs
  -> stateful-dependencies tfvars

network outputs + runtime-dependencies outputs + stateful-dependencies outputs + operator /32
  -> eks-runtime tfvars

verified internal ALB ARN + private frontend bucket name
  -> frontend-delivery tfvars
```

Network와 runtime-dependencies의 최초 operator input은 기존 `live.tfvars.example`을 복사해 작성한다. 실제 output을 필요로 하는 downstream stage만 generator로 만든다.

생성 파일은 `.tfvars` 확장자로 저장하며 Git에서 제외한다. workflow artifact, PR, issue 또는 채팅에 내용을 붙이지 않는다.

## Terraform output JSON 준비

각 applied state에서 다음처럼 output을 로컬 private artifact로 저장한다.

```powershell
New-Item -ItemType Directory -Force artifacts\terraform | Out-Null

terraform -chdir=infra\terraform\envs\aws-runtime-network output -json `
  | Set-Content -Encoding utf8 artifacts\terraform\network.json

terraform -chdir=infra\terraform\envs\backend-runtime-dependencies output -json `
  | Set-Content -Encoding utf8 artifacts\terraform\runtime-dependencies.json

terraform -chdir=infra\terraform\envs\backend-stateful-dependencies output -json `
  | Set-Content -Encoding utf8 artifacts\terraform\stateful-dependencies.json
```

`artifacts/`는 Git에서 제외된다.

## Stateful dependencies

```powershell
python scripts\deploy\build-live-stage-tfvars.py `
  --stage stateful-dependencies `
  --network-outputs-json artifacts\terraform\network.json `
  --output infra\terraform\envs\backend-stateful-dependencies\live.tfvars
```

Generator가 전달하는 값:

```text
vpc_id
private_subnet_ids
private_subnet_cidr_blocks -> allowed_database_cidr_blocks
```

고정 안전값:

```text
database_publicly_accessible=false
database_storage_encrypted=true
database_multi_az=false
database_apply_immediately=false
```

실제 plan 전에 삭제 보호, final snapshot, backup retention은 검증 기간과 cleanup 정책에 맞게 다시 검토한다.

## EKS runtime

현재 operator 공인 IP 조회 예:

```powershell
$OperatorIp = (Invoke-RestMethod https://checkip.amazonaws.com).Trim()
$OperatorCidr = "$OperatorIp/32"
```

Generator:

```powershell
python scripts\deploy\build-live-stage-tfvars.py `
  --stage eks-runtime `
  --network-outputs-json artifacts\terraform\network.json `
  --runtime-outputs-json artifacts\terraform\runtime-dependencies.json `
  --stateful-outputs-json artifacts\terraform\stateful-dependencies.json `
  --operator-cidr $OperatorCidr `
  --output infra\terraform\envs\eks-runtime\live.tfvars
```

Generator는 operator CIDR이 정확한 routable IPv4 `/32`가 아니면 실패한다. 다음 값은 거부된다.

```text
0.0.0.0/0
::/0
private IPv4
loopback/link-local/multicast
문서 예시용 예약 주소
```

전달 output:

```text
vpc_id
vpc_cidr_block
private_subnet_ids
upload_bucket_arn
result_bucket_arn
ai_log_queue_arn
terraform_log_queue_arn
backend_runtime_secret_arn
database_master_user_secret_arn
```

`database_master_user_secret_arn`은 실제 Secret 값이 아니라 RDS-managed Secret의 ARN metadata만 전달한다.

고정 안전값:

```text
kubernetes_version=1.35
node_desired_size=1
bedrock_model_resource_arns=[]
```

초기 controller 설치를 위해 public endpoint를 operator `/32`에만 임시 허용한다. 검증 종료 후 private-only 전환을 별도 plan으로 수행한다.

## Frontend delivery

Internal ALB가 실제 생성되고 다음 검증이 끝난 뒤에만 실행한다.

```text
scheme=internal
type=application
private subnet 2개 이상
target type=ip
backend targets=healthy
```

```powershell
$FrontendBucket = "replace-with-globally-unique-private-bucket"
$InternalAlbArn = "arn:aws:elasticloadbalancing:ap-northeast-2:123456789012:loadbalancer/app/example/0123456789abcdef"

python scripts\deploy\build-live-stage-tfvars.py `
  --stage frontend-delivery `
  --frontend-bucket-name $FrontendBucket `
  --api-origin-load-balancer-arn $InternalAlbArn `
  --output infra\terraform\envs\frontend-delivery\live.tfvars
```

Generator는 Application Load Balancer ARN 형식과 S3 bucket 이름 형식을 검사하고 `frontend_bucket_force_destroy=false`를 유지한다.

## GitHub environment Secret 등록

검토가 끝난 private tfvars만 base64로 변환한다.

```powershell
function Set-LiveTfvarsSecret {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $SecretName
    )

    $Encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))

    gh secret set $SecretName `
      --repo siamese-lang/Terraformers-modernization `
      --env aws-live-plan `
      --body $Encoded

    Remove-Variable Encoded
}
```

Secret 이름:

```text
AWS_LIVE_NETWORK_TFVARS_B64
AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64
AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64
AWS_LIVE_EKS_TFVARS_B64
AWS_LIVE_FRONTEND_TFVARS_B64
```

## 자동 검증

```powershell
python scripts\checks\live-stage-tfvars-builder-verification.py
```

정상 기준:

```text
live_stage_tfvars_builder_verification=passed
generated_stage_count=3
unsafe_operator_cidr_rejected=true
missing_stateful_outputs_rejected=true
secret_values_read=false
aws_authentication=none
aws_mutation=none
```
