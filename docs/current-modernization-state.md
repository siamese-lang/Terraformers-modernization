# Current Modernization State

## 1. Purpose

This document records the current `main` branch state after the core Terraformers modernization contracts and follow-up adapter contracts have been merged.

It is intentionally descriptive. It does not introduce new scope and it does not claim that the full original Terraformers service has been restored.

## 2. Validated main-branch baseline

As of the current checkpoint, the following validations have passed on `main`:

```text
Frontend Import Verification
Backend Local Verification
Runtime Contract Verification
```

`Runtime Contract Verification` now covers both infrastructure runtime boundaries and selected backend API contract tests.

## 3. Recent merged checkpoint

The current checkpoint includes the following completed PR sequence:

```text
PR #6 OpenSearch reference retriever contract
PR #7 Bedrock prompt reference-context integration
PR #8 Backend verification diagnostics improvement
PR #9 Runtime verification backend API contract coverage
```

This sequence should be treated as a stable post-modernization baseline. Further work should start from a new branch and should not reopen or expand the completed PRs.

## 4. Product contract now represented in backend tests

The backend contract now preserves the main original Terraformers product path at a testable API-contract level:

```text
architecture image upload
  -> analysis job bridge
  -> project metadata
  -> project tree
  -> Terraform main.tf draft preview
  -> public project listing
  -> public project comments
```

Covered API surfaces include:

```text
POST /api/upload
GET  /api/projects
GET  /api/projects/{projectId}
GET  /api/projects/public
GET  /api/public-projects
GET  /api/project-tree
GET  /api/project-tree/{projectId}
GET  /api/projects/{projectId}/terraform/main.tf
PUT  /api/projects/{projectId}/terraform/main.tf
GET  /api/projects/{projectId}/comments
POST /api/projects/{projectId}/comments
GET  /api/getProjectComments/{projectId}
POST /api/addProjectComment
```

## 5. Runtime and adapter boundaries now represented

The current backend/runtime boundary includes:

```text
UploadObjectStorageService
  -> metadata-only local/test mode
  -> opt-in S3 writer mode

ObjectReader
  -> source object metadata/content boundary

ReferenceRetriever
  -> stub fallback
  -> opt-in OpenSearch HTTP retriever boundary

BedrockRuntimeAnalysisProvider
  -> source metadata lookup
  -> retrieved reference context injection
  -> Bedrock prompt/request/response contract

AnalysisProgressPublisher
  -> optional SQS progress publisher boundary
```

These are contract and adapter boundaries. Production operation still requires environment-specific AWS resources, IAM, secrets, and manual production validation workflows where applicable.

## 6. Verification workflows

Current workflow roles:

```text
Frontend Import Verification
  -> verifies frontend import/build compatibility only

Backend Local Verification
  -> runs backend Maven test baseline
  -> packages backend without re-running tests
  -> uploads diagnostics artifact on failure

Runtime Contract Verification
  -> renders Kubernetes base safely
  -> checks no placeholder Secret is rendered by base
  -> validates Terraform runtime contract
  -> runs selected backend API contract tests

S3 Writer Production Validation
  -> optional manual evidence path for real S3 object persistence
```

## 7. Current non-claims

The current branch does not claim the following:

```text
browser image download/preview from S3
OpenSearch production deployment validation
Bedrock production invocation evidence
SQS production polling UI
Terraform plan/apply/destroy execution
Terraform tfstate API
Cognito login restoration
browser AWS credential settings
full original dashboard restoration
nested comments / likes / ownership controls
production EKS rollout evidence
```

These are either explicitly excluded or require separate, smaller PRs with their own validation gates.

## 8. Recommended next PR candidates

Choose only one next PR at a time.

Most useful remaining candidates are:

```text
1. README and portfolio explanation update
2. Optional S3 writer production evidence run, if AWS bucket/IAM are ready
3. SQS publisher/log contract refinement
4. Cognito/auth boundary documentation or minimal backend contract
5. Bedrock/OpenSearch production validation only if credentials and endpoints are available
```

Do not add Terraform execution, tfstate APIs, or browser AWS credential controls unless the project direction is explicitly changed.

## 9. Portfolio explanation

```text
Terraformers 현대화 작업은 원본 팀 프로젝트의 핵심 제품 흐름을 그대로 다시 만드는 것이 아니라, 이미지 업로드에서 분석 job, 프로젝트 메타데이터, 프로젝트 트리, Terraform main.tf preview, 공개 프로젝트와 댓글까지 이어지는 흐름을 Spring Boot backend의 검증 가능한 API 계약으로 정리한 작업입니다. 또한 S3 writer, ObjectReader, OpenSearch retriever, Bedrock Runtime provider, SQS publisher 같은 외부 의존성은 한 번에 production 복원하지 않고, local/test 기본 경로와 opt-in adapter 경계로 분리했습니다. 이를 통해 기능 시연 중심이었던 팀 프로젝트를 백엔드 구조, runtime config, 외부 AWS 의존성, CI 검증, 실패 진단 관점에서 설명 가능한 상태로 고도화했습니다.
```
