# Terraformers Modernization

## Lifecycle 상태

| 구분 | 정확한 상태 |
|---|---|
| `last_verified_deployed_architecture` | EKS Backend, RDS, S3, Cognito, Bedrock, private AOSS, CloudFront private origin, External Secrets/IRSA, immutable ECR digest와 Argo CD GitOps를 사용한 마지막 검증 배포 구조 |
| `current_aws_runtime_status` | 현재 실행 중인 AWS runtime 없음 |
| `runtime_teardown_status` | verified — read-only runtime closure run `29904386655` passed; six runtime Terraform states와 exact active runtime AWS resource count가 모두 0 |
| `bootstrap_closure_status` | bootstrap inventory passed; deletion not approved/not executed; zero-resource proof incomplete |

이 README의 기능·아키텍처·workload 설명은 **현재 online service의 주장**이 아니라 마지막으로 검증된 배포와 저장소 구현 범위다. Bootstrap deletion과 full-zero-state redeployment는 아직 실행되지 않았다. 상세 canonical source는 [`docs/project-system-overview.md`](docs/project-system-overview.md)다.

## 1. 프로젝트 개요

**Terraformers Modernization**은 2024년 AWS Cloud School 5인 팀 프로젝트 `Terraformers`를 기반으로, 기존 산출물을 현재 기준의 **백엔드·클라우드 인프라 운영환경 고도화 프로젝트**로 정리한 저장소입니다.

원본 서비스는 사용자가 AWS 아키텍처 이미지를 업로드하면 AI 분석 결과를 바탕으로 Terraform 코드 초안을 생성하고, 프로젝트·파일·결과·댓글 등 관련 데이터를 웹에서 관리합니다.

이 저장소의 목적은 서비스를 새로 만들거나 생성 AI 자체를 연구하는 것이 아닙니다. 기존 팀 결과물과 `siamese-lang/rdb-refactor`를 재사용하면서 다음을 보강했습니다.

- Spring Boot API와 owner-based RDB domain
- Flyway migration과 Hibernate schema validation
- Cognito 사용자와 내부 사용자·프로젝트 소유권 연결
- S3 object와 RDB metadata 책임 분리
- Spring Boot 내부 Bedrock/AOSS 분석 orchestration
- EKS, RDS, S3, SQS, Cognito, CloudFront, IAM, Secrets Manager Terraform 구성
- External Secrets와 IRSA 기반 Secret·AWS 권한 전달
- immutable ECR digest와 Argo CD GitOps
- 승인형 Terraform plan/apply
- CloudWatch/Application Signals/X-Ray 기반 관측성
- AWS 전체 철거·재배포 lifecycle 문서화

프로젝트 전체 구조를 가장 먼저 이해하려면 다음 문서를 읽습니다.

- **[`docs/project-system-overview.md`](docs/project-system-overview.md): 기능, 요청 흐름, Backend·AWS 구성, 주요 설정과 설계 이유를 연결한 전체 안내서**
- [`docs/current-operations-delivery-plan.md`](docs/current-operations-delivery-plan.md): 현재 종료 단계와 작업 순서
- [`docs/portfolio/final-evidence-and-interview-guide.md`](docs/portfolio/final-evidence-and-interview-guide.md): 최종 증빙과 면접 설명

## 2. 포트폴리오 제목

```text
Terraformers: 백엔드·클라우드 인프라 운영환경 고도화
```

영문 보조 제목:

```text
Terraformers Backend & Cloud Infrastructure Modernization
```

## 3. 마지막 검증 서비스 기능

- Cognito 회원가입·로그인
- 공개 프로젝트 조회
- 인증 사용자의 프로젝트 생성과 이미지 업로드
- 비동기 architecture analysis job 실행과 상태 조회
- Bedrock architecture facts 추출
- Titan embedding과 private AOSS vector retrieval
- reference-aware Terraform 코드 초안 생성
- 프로젝트 file tree와 원본 이미지·Terraform artifact 조회
- Terraform `main.tf` 편집
- 프로젝트 공개/비공개 전환과 soft-delete
- 공개 프로젝트 댓글

생성된 Terraform은 **검토 가능한 초안**이며 자동으로 `terraform apply`되지 않습니다.

## 4. 마지막 검증 배포 아키텍처

```text
User Browser
  |
  | HTTPS
  v
CloudFront
  |-- static route -> private versioned S3 through OAC
  |-- /api/*       -> VPC origin -> internal ALB
  v
Spring Boot Backend on EKS
  |-- Cognito JWT validation and RDB user mapping
  |-- RDS MariaDB: users/projects/files/analysis_jobs/comments
  |-- S3: architecture images and generated Terraform artifacts
  |-- Bedrock: architecture facts and Terraform draft generation
  |-- private AOSS: version-filtered vector retrieval
  |-- SQS: available progress/result adapter; current publisher disabled
  |-- CloudWatch/Application Signals/X-Ray: bounded telemetry
  |-- Secrets Manager -> External Secrets -> Kubernetes Secret
```

기존 Python analysis service는 팀 프로젝트의 historical reference입니다. 현재 기본 runtime에서는 **Spring Boot Backend가 analysis job lifecycle과 AWS adapter orchestration을 소유**합니다.

핵심 공개 경계:

```text
CloudFront only
  -> private S3 frontend
  -> private VPC origin
     -> internal ALB
        -> ClusterIP Backend Service / Pod IP
```

직접 public ALB, public AOSS, public Argo CD endpoint는 사용하지 않습니다.

## 5. Backend와 데이터 책임

### Backend

- Cognito access token 검증
- Cognito `sub`와 RDB user 매핑
- owner/public/admin authorization
- project, file, comment, analysis API
- analysis job 상태 전이
- Bedrock/AOSS/S3 adapter orchestration
- 생성 Terraform 검증·저장
- safe failure reason과 telemetry 기록

### RDS MariaDB

```text
users
  └─ projects
       ├─ project_files
       ├─ analysis_jobs
       ├─ terraform_runs
       └─ boards
            ├─ comments
            └─ board_reactions
```

RDB는 관계, 소유권, visibility, soft-delete, analysis status와 object metadata를 관리합니다.

### S3

- 업로드 architecture image bytes
- 생성 Terraform result bytes
- frontend static bundle
- RAG corpus package/receipt
- Terraform remote state

S3 object와 RDB metadata가 서로 다른 책임을 가지므로 운영 검증에서는 양쪽 상태를 함께 확인합니다.

## 6. 주요 기술과 설정

| 영역 | 마지막 검증 기준 |
|---|---|
| Backend | Java 17, Spring Boot 3.3.2, Spring Data JPA |
| Schema | Flyway, production `ddl-auto=validate` |
| Database | RDS MariaDB |
| Auth | Cognito + OAuth2 resource-server JWT |
| Object storage | private/versioned S3 |
| Analysis | Bedrock + Titan embedding + private AOSS |
| Runtime | EKS managed node group |
| Secret | RDS managed password + External Secrets |
| Public delivery | CloudFront, private S3 OAC, private ALB VPC origin |
| Image delivery | immutable ECR tag/digest + Argo CD |
| Infrastructure | seven remote Terraform state components |
| CI/CD identity | GitHub Actions OIDC |
| Observability | CloudWatch, Container Insights, Application Signals, X-Ray, Micrometer |

AWS runtime RAG 설정:

```text
analysis mode       integrated-java
retrieval mode      REQUIRED
generation model    global.anthropic.claude-sonnet-4-6
embedding model     amazon.titan-embed-text-v2:0
vector dimension    1024
physical index      terraformers-reference-v1
selected corpus     terraformers-reference-v2
provider version    5.100.0
topK                8
```

## 7. Terraform state 구성

| State | 주요 책임 |
|---|---|
| `bootstrap` | state bucket, plan/apply roles, GitHub OIDC create-or-adopt boundary |
| `network` | VPC, subnet, route, NAT, endpoint |
| `runtime-dependencies` | ECR, upload/result S3, SQS, runtime Secret container |
| `stateful-dependencies` | RDS, Cognito |
| `eks-runtime` | EKS, node group, IRSA, observability |
| `rag-runtime` | AOSS, corpus bucket, CodeBuild ingestion |
| `frontend-delivery` | frontend S3/OAC, CloudFront, VPC origin |

The bootstrap root can conditionally create a GitHub OIDC provider or adopt an existing provider ARN. The current live bootstrap state adopted an existing project-dedicated GitHub OIDC provider, so the provider itself is outside the 16 managed bootstrap addresses and requires separate final deletion; plan/apply roles remain in bootstrap state.

Terraform apply는 merge 시 자동 실행하지 않습니다. Live plan을 검토한 뒤 protected environment와 exact approved contract를 통해 별도로 실행합니다.

## 8. GitOps delivery

```text
Backend source commit
  -> GitHub OIDC image workflow
  -> immutable git-<full-sha> tag
  -> ECR digest
  -> digest-only GitOps pull request
  -> integration merge
  -> Argo CD reconciliation
  -> Deployment image / Pod imageID parity
```

Image workflow는 `kubectl apply`나 `kubectl set image`를 실행하지 않습니다. Rollback은 이전 digest를 가리키는 Git commit으로 되돌립니다.

마지막 검증 Backend workload 기준:

- namespace `terraformers-runtime`
- Deployment replica 1
- Service `ClusterIP`
- UID 10001, non-root, RuntimeDefault seccomp
- startup/readiness/liveness probes
- requests 250m/512Mi, limits 1CPU/1Gi
- Java auto-instrumentation annotation

단일 replica이므로 application high availability를 구현했다고 주장하지 않습니다.

## 9. 검증 흐름

PR 단계:

```text
Backend Local Verification
Frontend CI
Terraform Static Verification
Runtime Contract Verification
Backend Origin Contract Verification
Pre-deployment Package Verification
```

승인 delivery 단계:

```text
Terraform live plan -> reviewed apply
Backend image publish -> GitOps digest PR -> Argo CD
RAG package -> private CodeBuild ingestion
Frontend build -> private S3 sync -> limited CloudFront invalidation
Browser/API/runtime/telemetry evidence
```

Workflow 성공만으로 실제 서비스 완료를 판단하지 않습니다. Git desired state, Pod runtime image, browser outcome, RDB/S3 상태와 telemetry를 함께 확인합니다.

## 10. 팀 프로젝트와 후속 고도화 구분

### 팀 프로젝트 당시

- 5인 팀이 architecture image 기반 Terraform 생성 서비스를 구현
- 백엔드 일부 기능과 배포 흐름 점검에 참여
- S3, 인증, 결과 조회 등 서비스 흐름 검증에 참여

### 후속 개인 고도화

- 원본과 `rdb-refactor` 비교 및 재사용 범위 결정
- canonical RDB domain과 인증/소유권 정렬
- Spring Boot 통합 분석 runtime 구현·검증
- AWS Terraform state와 실제 배포 복구
- private RAG와 corpus v2 비교
- External Secrets와 private origin
- immutable digest GitOps
- AWS-native observability
- 장애 원인·수정·검증 기록
- AWS inventory, teardown, redeployment runbook

2024년 팀 구현 전체를 개인 작업으로 설명하지 않습니다.

## 11. 주요 문서

### 전체 이해와 방향

- [`docs/project-system-overview.md`](docs/project-system-overview.md)
- [`docs/current-operations-delivery-plan.md`](docs/current-operations-delivery-plan.md)
- [`docs/source-rag-gitops-reuse-plan.md`](docs/source-rag-gitops-reuse-plan.md)

### Backend와 데이터

- [`docs/rdb-domain-realignment.md`](docs/rdb-domain-realignment.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/deployment.md`](docs/deployment.md)

### Delivery와 운영

- [`docs/gitops-delivery.md`](docs/gitops-delivery.md)
- [`docs/backend-origin-delivery.md`](docs/backend-origin-delivery.md)
- [`docs/frontend-delivery.md`](docs/frontend-delivery.md)
- [`docs/managed-secret-delivery.md`](docs/managed-secret-delivery.md)
- [`docs/terraform-rag-runtime.md`](docs/terraform-rag-runtime.md)
- [`docs/operations-visibility.md`](docs/operations-visibility.md)

### 종료와 면접

- [`docs/portfolio/final-evidence-and-interview-guide.md`](docs/portfolio/final-evidence-and-interview-guide.md)
- [`docs/lifecycle/aws-resource-inventory.md`](docs/lifecycle/aws-resource-inventory.md)
- [`docs/lifecycle/aws-teardown-runbook.md`](docs/lifecycle/aws-teardown-runbook.md)
- [`docs/lifecycle/aws-redeploy-runbook.md`](docs/lifecycle/aws-redeploy-runbook.md)
- [`docs/lifecycle/aws-runtime-teardown-closure.md`](docs/lifecycle/aws-runtime-teardown-closure.md)
- [`docs/lifecycle/closure-progress.md`](docs/lifecycle/closure-progress.md)

## 12. 의도적으로 주장하지 않는 범위

- 생성 Terraform의 자동 배포 가능성
- HPA/JMeter autoscaling 완료
- 다중 Backend replica 기반 HA
- multi-region disaster recovery
- RDS restore drill 완료
- 모든 AWS 리소스의 Terraform-only 관리
- 통계적으로 충분한 RAG 품질 평가
- 최종 live evidence가 없는 telemetry 성공

## 13. 핵심 설명 문장

```text
팀 프로젝트에서는 기능 완성과 시연에 집중했지만, 이후 실제 서비스로 설명하려면 데이터 소유권, DB schema 정합성, AWS 의존성 연결, Secret 전달, 인프라 변경 통제, image와 runtime 일치, 관측성과 장애 대응, 전체 환경의 철거·재배포 절차가 필요하다고 판단했습니다. 그래서 기존 Terraformers와 RDB refactor 결과를 재사용해 Spring Boot 통합 분석 runtime, owner-based RDB domain, private AWS architecture, immutable digest GitOps, 승인형 Terraform과 운영 runbook을 연결했습니다.
```
