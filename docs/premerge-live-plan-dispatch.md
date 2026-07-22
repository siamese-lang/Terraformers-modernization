# Pre-merge Live Terraform Plan Dispatch

## 왜 standalone workflow를 직접 실행하지 않는가

GitHub의 `workflow_dispatch` 이벤트는 workflow 파일이 기본 branch에 존재할 때만 등록된다.

Draft PR #32 동안 `.github/workflows/aws-live-terraform-plan.yml`은 `agent/rdb-domain-realignment`에만 있으므로 다음 직접 dispatch는 merge 전에는 사용하지 않는다.

```powershell
gh workflow run aws-live-terraform-plan.yml `
  --repo siamese-lang/Terraformers-modernization `
  --ref agent/rdb-domain-realignment
```

`--ref`는 실행할 branch 버전을 선택하지만, 기본 branch에 없는 workflow를 새로 등록하지는 않는다.

## 등록된 pre-merge 진입점

기본 branch에 이미 등록된 workflow를 사용한다.

```text
.github/workflows/runtime-contract-verification.yml
```

Branch 버전은 다음 입력을 제공한다.

```text
execute_live_plan
plan_stage
expected_aws_account_id
allow_destructive
allow_optional_adapters
```

`execute_live_plan=true`이면 다음 same-commit reusable workflow를 호출한다.

```text
./.github/workflows/aws-live-terraform-plan.yml
```

같은 저장소의 상대 경로 reusable workflow는 caller와 동일한 commit의 파일을 사용한다. 따라서 default branch에 아직 merge되지 않은 Draft branch의 live-plan 구현을 복사하지 않고 실행할 수 있다.

## 현재 허용된 pre-merge 범위

현재 단계에서는 `network` plan만 실행한다.

```text
plan_stage=network
allow_destructive=false
allow_optional_adapters=false
```

필수 조건:

- `aws-live-plan` protected environment 존재
- environment variable 4개 등록
- `AWS_LIVE_NETWORK_TFVARS_B64` 등록
- network strict prerequisite 통과
- expected AWS account ID 일치
- GitHub OIDC role trust 일치

이 경로는 다음 작업을 수행하지 않는다.

- Terraform apply/destroy
- Kubernetes apply
- Helm install/upgrade
- image/ECR push
- S3 sync
- CloudFront invalidation

## 실행 명령

Git Bash에서 다음 wrapper를 사용한다.

```bash
bash scripts/deploy/dispatch-premerge-network-plan.sh \
  --expected-head "<exact-head-sha>"
```

Wrapper는 private foundation tfvars에서 expected account ID를 읽지만 화면에 출력하지 않는다. Dispatch 전에 network strict prerequisite를 다시 확인하고, 다음 registered workflow를 현재 branch ref로 실행한다.

```text
runtime-contract-verification.yml
```

정상 출력에는 run ID와 GitHub Actions URL이 포함된다. `aws-live-plan` environment reviewer 승인을 완료하면 reusable workflow가 OIDC로 AWS에 인증하고 remote state를 사용해 network plan을 생성한다.

## 산출물 경계

업로드 허용:

- sanitized plan risk summary
- resource action count
- blocked risk count
- plan/input/provider-lock SHA-256
- plan-only execution summary

업로드 금지:

- raw private tfvars
- raw plan JSON
- binary `.tfplan`
- AWS credential
- Secret 값

## Merge 이후

`.github/workflows/aws-live-terraform-plan.yml`이 `main`에 존재하면 standalone workflow가 직접 등록된다. 그 이후에는 runtime-contract workflow를 경유하지 않고 standalone workflow를 실행할 수 있다.

Workflow 등록 여부는 Terraform apply 승인과 별개다. Network apply는 sanitized plan 검토 후 별도로 승인한다.
