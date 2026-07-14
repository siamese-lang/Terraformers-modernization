# Public Repository Migration Plan

## 1. 목적

이 문서는 기존 private 작업물에서 `siamese-lang/Terraformers-modernization` 공개 저장소로 이전할 범위와 제외할 범위를 정리한다.

이전 목적은 private 저장소 전체 이력을 그대로 공개하는 것이 아니다. 목적은 Terraformers 팀 프로젝트의 후속 고도화 결과를 **백엔드 개발과 클라우드 인프라 구축·관리 중심의 공개 포트폴리오 저장소**로 재구성하는 것이다.

## 2. 이전 원칙

### 2.1 공개 가능한 것만 이전한다

다음 항목은 공개 저장소로 이전할 수 있다.

- 본인이 후속 고도화한 backend 코드
- secret value가 제거된 runtime config contract
- Flyway migration
- backend Dockerfile
- backend tests and smoke scripts
- Terraform modules and environment structure
- Kubernetes manifests with placeholder/example values
- GitHub Actions workflows using repository secrets/variables
- 운영 검증 문서와 runbook
- sanitized evidence template

### 2.2 민감 정보는 절대 이전하지 않는다

다음 항목은 공개 저장소에 포함하지 않는다.

- AWS account id
- access key / secret key / session token
- GitHub token
- DB password
- Cognito secret
- private ARN values that identify the real account unnecessarily
- actual `.env`, `terraform.tfvars`, kubeconfig, SSH key
- Terraform state file
- 실제 운영 로그 중 token/password/secret/account id가 포함된 내용
- S3 bucket object path 중 개인 계정이나 민감 정보를 노출하는 값

### 2.3 팀 프로젝트 기여 범위를 왜곡하지 않는다

공개 저장소는 후속 고도화 결과를 정리하는 저장소다.

따라서 다음처럼 설명하지 않는다.

- 원본 팀 프로젝트 전체를 혼자 개발했다고 설명하지 않는다.
- frontend 전체 개발을 본인 기여로 설명하지 않는다.
- AI 생성 품질 고도화를 본인 핵심 기여로 설명하지 않는다.
- 팀원의 코드까지 본인 단독 구현물처럼 보이게 하지 않는다.

## 3. 이전 대상 우선순위

## Phase 1. Repository baseline

상태: 완료.

이전/생성 대상:

- `README.md`
- `PROJECT_DIRECTION.md`
- `docs/backend-infra-scope.md`
- `docs/migration-plan.md`
- `docs/architecture.md`
- `docs/deployment.md`
- `docs/validation.md`
- `docs/runbook.md`
- `docs/interview-guide.md`
- `.gitignore`

완료 기준:

- 저장소 첫 화면에서 프로젝트 정체성이 명확해야 한다.
- 작업 중심이 backend와 cloud infrastructure임이 드러나야 한다.
- 금지 방향이 문서에 고정되어야 한다.

## Phase 2. Backend source import

상태: 부분 진행.

현재 공개 저장소에는 전체 원본 backend source가 아니라 **public-safe backend modernization baseline**을 먼저 추가했다. 검증 목표와 한계는 `docs/notes/backend-baseline-validation.md`에 정리한다.

현재 추가된 항목:

```text
backend/
  pom.xml
  Dockerfile
  README.md
  src/main/java/com/terraformers/modernization/
  src/main/resources/application.yml
  src/main/resources/application-prod.yml
  src/main/resources/db/migration/V20260714_001__baseline_backend_schema.sql
  src/test/java/com/terraformers/modernization/config/RuntimeConfigInspectorTest.java
  src/test/java/com/terraformers/modernization/web/RuntimeReadinessControllerTest.java
  src/test/java/com/terraformers/modernization/TerraformersBackendApplicationTest.java

.github/workflows/backend-maven-verification.yml
.github/workflows/backend-image-build.yml
scripts/checks/backend-local-verification.sh
docs/backend-public-baseline.md
docs/notes/backend-baseline-validation.md
```

기존 이전 대상:

```text
backend/
  mini/
    pom.xml
    Dockerfile
    src/main/java/...
    src/main/resources/...
    src/test/...
```

정리 기준:

- 원본 경로를 그대로 노출하기보다 공개 저장소의 목적에 맞게 `backend/` 중심으로 재배치한다.
- 사용하지 않는 legacy dependency를 제거한다.
- production code에 DynamoDB persistence가 남아 있다면 제거하거나 명확히 legacy로 분리한다.
- `application-prod.properties`는 secret value 없이 env contract만 남긴다.
- local/dev example은 실제 credential 없이 placeholder만 둔다.
- Maven compile/test가 통과해야 한다.

완료 기준:

```bash
cd backend
mvn -q test
mvn -q -DskipTests package
docker build -t terraformers-backend:local .
```

위 명령이 공개 저장소 기준으로 동작해야 한다.

## Phase 3. Backend schema and smoke scripts

이전 대상:

```text
backend/src/main/resources/db/migration/
scripts/smoke/
scripts/checks/
```

정리 기준:

- Flyway migration을 canonical schema 변경 이력으로 둔다.
- 수동 hotfix SQL은 emergency reference로만 분리한다.
- smoke script는 실제 token/secret 없이 env var placeholder를 사용한다.
- API smoke는 health, public API, protected API 401/200, upload, project tree, SQS polling을 단계적으로 확인한다.

완료 기준:

- schema validation 기준이 문서화되어야 한다.
- smoke script 실행 방법이 `docs/validation.md`에 연결되어야 한다.

## Phase 4. Cloud infrastructure import

이전 대상:

```text
infra/terraform/
  envs/dev/
  modules/network/
  modules/eks/
  modules/ecr/
  modules/rds-mariadb/
  modules/s3/
  modules/sqs/
  modules/cognito/
  modules/iam/
  modules/secretsmanager/
  modules/cloudfront/

infra/kubernetes/
  backend/
  bedrock/
  secrets/
  argocd/
```

정리 기준:

- 실제 tfstate, tfvars, account-specific 값은 제외한다.
- `terraform.tfvars.example`만 제공한다.
- resource name은 dev/example 기준으로 일반화한다.
- IAM policy는 최소 권한 방향으로 정리하되, 실제 운영 검증 전까지 과장하지 않는다.
- External Secrets를 사용할 경우 CRD 설치 여부와 비활성 dev 경로를 분리한다.

완료 기준:

```bash
cd infra/terraform/envs/dev
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

위 검증이 공개 저장소 기준으로 동작해야 한다.

## Phase 5. GitHub Actions workflows

이전 대상:

```text
.github/workflows/backend-maven-verification.yml
.github/workflows/backend-image-build.yml
.github/workflows/backend-image-publish.yml
.github/workflows/bedrock-image-publish.yml
.github/workflows/terraform-plan.yml
.github/workflows/terraform-apply.yml
```

정리 기준:

- PR 단계와 운영 반영 단계를 분리한다.
- AWS 접근은 OIDC role assume을 기준으로 한다.
- workflow에는 real secret을 쓰지 않고 `${{ secrets.* }}`와 `${{ vars.* }}`만 사용한다.
- Terraform plan/apply log에 secret value가 출력되지 않도록 한다.
- image publish workflow는 ECR repository 존재 여부를 확인한다.
- manifest image tag update commit을 통해 runtime 반영 이력을 남긴다.

완료 기준:

- PR validation workflow가 공개 저장소에서 실행 가능해야 한다.
- AWS 배포 workflow는 필요한 repository variables/secrets가 문서화되어야 한다.

## Phase 6. Evidence and final README polish

이전/생성 대상:

```text
docs/evidence/README.md
docs/evidence/templates/
```

정리 기준:

- 실제 secret/account id는 포함하지 않는다.
- 검증 결과는 명령, 기대 결과, 마스킹 기준을 중심으로 남긴다.
- “실제 배포 완료”와 “코드/문서상 구성 정의”를 구분한다.

완료 기준:

- README에서 evidence 문서로 자연스럽게 연결되어야 한다.
- 면접에서 보여 줄 수 있는 검증 항목이 정리되어야 한다.

## 4. 제외 대상

다음은 기본적으로 공개 저장소로 이전하지 않는다.

- private repository git history 전체
- 실제 운영 계정 기준 tfstate
- 실제 `.env`, `terraform.tfvars`, kubeconfig
- frontend 전체 소스 전체 이전. 단, E2E 검증에 필요한 최소 surface는 별도 판단
- AI prompt/model 성능 개선 중심 실험 코드
- 특정 팀원의 개인 작업물로 보일 수 있는 미정리 코드
- 불필요한 대용량 파일, 이미지, PDF, binary artifact

## 5. 공개 전 검토 checklist

코드나 문서를 공개 저장소에 추가하기 전에 다음을 확인한다.

```text
[ ] AWS access key가 없는가?
[ ] GitHub token이 없는가?
[ ] DB password가 없는가?
[ ] Cognito secret이 없는가?
[ ] terraform.tfstate가 없는가?
[ ] terraform.tfvars 실제 값이 없는가?
[ ] kubeconfig가 없는가?
[ ] private ARN/account id가 불필요하게 노출되지 않는가?
[ ] 팀 프로젝트 전체를 단독 구현처럼 보이게 하지 않는가?
[ ] frontend/AI 생성 품질 중심으로 주제가 흐르지 않는가?
[ ] backend와 cloud infrastructure 중심 설명이 유지되는가?
```

## 6. 다음 작업

다음 순서로 진행한다.

1. 공개 backend baseline의 GitHub Actions 실행 결과를 확인한다.
2. private 작업물에서 실제 domain/entity/repository/service 코드를 선별한다.
3. secret/config 값이 없는지 점검한다.
4. 공개 저장소의 `backend/` 경로에 맞게 재배치한다.
5. Maven compile/test 기준을 맞춘다.
6. backend smoke script를 추가한다.
7. Terraform env/module을 선별 이전한다.
8. Terraform fmt/init/validate 기준을 맞춘다.
9. GitHub Actions workflow를 공개 저장소 경로에 맞게 수정한다.
10. validation/runbook 문서를 실제 코드 경로에 맞게 보정한다.
