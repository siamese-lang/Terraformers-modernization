# Live AWS Foundation State Migration

## 목적

실제 AWS foundation apply 이후 bootstrap Terraform state를 versioning이 활성화된 private S3 backend로 이전하고, 이전 전 local backup과 remote state가 같은 인프라 상태를 나타내는지 검증한 결과를 기록한다.

이 문서는 계정 ID, bucket 이름, role ARN, state 원문, private tfvars를 포함하지 않는다.

## 완료 상태

실행일:

```text
2026-07-17
```

최종 reconciliation repository head:

```text
f70f157deccacd721f4c6864f6dd91add120c00f
```

검증된 결과:

```text
Terraform CLI                       1.15.8
remote backend                      S3
state locking                       S3 native .tflock
remote state version count          1
managed resource count              9
resource payload                    exact
output payload                      exact
check result count                  7
check result status                 all pass
check result difference             top-level order only
lineage                             rebased during migration
remote serial                       valid new-lineage serial
post-migration plan                 no changes
stale lock object                   absent
local pre-migration backup          preserved
reconciliation AWS mutation         none
provider runtime                    fresh isolated TF_DATA_DIR
```

## State 동등성 판정

Remote state는 local pre-migration backup과 다음 항목이 일치했다.

- managed resource address 9개
- `resources` 전체 payload
- `outputs` 전체 payload
- `check_results` 7개 항목의 내용과 `pass` status

`check_results` 배열의 최상위 순서만 달랐으며 canonical JSON 정렬 후에는 동일했다.

Migration 과정에서 remote state는 새 lineage와 serial 1로 시작했다. 서로 다른 lineage의 serial은 동일 계열의 증가값으로 직접 비교하지 않는다. 대신 다음 조건을 모두 만족해야만 새 remote lineage를 canonical state로 인정했다.

- resource payload exact
- output payload exact
- check-result semantic equivalence
- 모든 check status가 `pass`
- remote serial이 1 이상
- `terraform plan -refresh=false -lock=false -detailed-exitcode`가 exit code 0
- S3 native `.tflock` 잔여 object 없음

## Provider runtime 격리

기존 로컬 AWS provider executable이 schema 요청에서 응답하지 않는 문제가 한 차례 발생했다. State migration은 다시 실행하지 않았고, 저장소 밖의 fresh `TF_DATA_DIR`에서 AWS provider 5.100.0을 다시 설치한 뒤 다음을 확인했다.

```text
ProviderRuntimeIsolation=success
ProviderSchemaLoaded=true
TerraformDataDirectory=private-isolated
RemoteStateWriteAttempted=false
```

이는 state 또는 AWS resource 문제가 아니라 기존 local provider runtime 문제였으며, 격리 환경에서 schema와 no-change plan이 정상 동작했다.

## 보존 파일

다음 파일은 저장소 밖의 local private directory에 유지한다.

```text
foundation.local-pre-migration.tfstate
foundation.local-pre-migration.tfstate.sha256
foundation.backend.hcl
foundation.remote-post-migration.tfstate
foundation.state-reconciliation.json
foundation.post-migration.tfplan
foundation.post-migration-plan.log
```

State·plan·diagnostic 원문은 GitHub, issue, PR, workflow artifact에 업로드하지 않는다.

## 이후 운영 기준

Bootstrap foundation의 canonical state는 다음 S3 key 계약을 사용한다.

```text
<state-prefix>/bootstrap/terraform.tfstate
<state-prefix>/bootstrap/terraform.tfstate.tflock
```

다음 단계 state는 동일한 bucket에서 stage별 key를 사용한다.

```text
<state-prefix>/network/terraform.tfstate
<state-prefix>/runtime-dependencies/terraform.tfstate
<state-prefix>/stateful-dependencies/terraform.tfstate
<state-prefix>/eks-runtime/terraform.tfstate
<state-prefix>/frontend-delivery/terraform.tfstate
```

각 state write는 별도 reviewed plan과 명시적 승인 이후에만 수행한다.

## 다음 단계

```text
aws-live-plan protected environment 생성
  -> environment variables 등록
  -> five private tfvars Secrets 등록
  -> strict prerequisite inventory
  -> network plan only
```

Network apply, runtime/RDS/EKS 생성, Kubernetes/Helm mutation은 별도 승인 전에는 수행하지 않는다.
