# Backend and Cloud Infrastructure Modernization Scope

## 1. 목적

이 문서는 Terraformers Modernization의 작업 범위를 **백엔드 개발**과 **클라우드 인프라 구축·관리** 중심으로 고정하기 위한 문서다.

이 프로젝트는 AI 생성 품질 개선이나 frontend 개발을 중심으로 하지 않는다. 원본 Terraformers 팀 프로젝트의 서비스 흐름을 유지하되, 포트폴리오에서는 다음 질문에 답할 수 있어야 한다.

```text
이 웹서비스의 backend는 어떤 데이터를 어떤 기준으로 저장하고,
AWS 관리형 서비스와 어떻게 연동되며,
어떤 인프라와 배포 절차를 통해 운영 가능한 상태로 검증되는가?
```

## 2. Core Scope: Backend Development

### 2.1 Backend API 구조 정리

정리 대상:

- 인증 사용자 기준 API 흐름
- 프로젝트 생성·조회·공개 전환 흐름
- 파일 업로드와 결과 조회 흐름
- 댓글과 공개 프로젝트 조회 흐름
- AI/Terraform 처리 로그 polling 흐름
- backend health check와 actuator endpoint

완료 기준:

- API별 입력, 출력, 인증 필요 여부가 문서화되어야 한다.
- 주요 API가 어떤 table, S3 object, SQS queue와 연결되는지 설명 가능해야 한다.
- 잘못된 인증, 잘못된 projectId, 잘못된 queueUrl, 누락된 fileId 같은 실패 상황을 구분할 수 있어야 한다.

### 2.2 RDB 중심 persistence 구조

정리 대상:

- users
- projects
- project_files
- boards
- comments
- reactions
- terraform_runs 또는 실행 이력성 데이터

운영 기준:

- 관계형 업무 데이터의 source of truth는 RDB로 둔다.
- 실제 파일 content는 S3에 두고, RDB에는 metadata와 관계를 저장한다.
- DynamoDB 등 legacy persistence가 production backend에 재도입되지 않도록 guard를 둔다.

완료 기준:

- ERD 또는 table responsibility 문서가 있어야 한다.
- Flyway migration이 schema 변경 이력의 기준이어야 한다.
- Hibernate `ddl-auto=validate` 기준으로 schema drift를 조기에 발견할 수 있어야 한다.

### 2.3 AWS dependency integration

정리 대상:

- S3: 업로드 이미지, 생성 Terraform 파일, tfstate object
- SQS: AI/Terraform 진행 로그와 결과 메시지
- Cognito: access token 검증과 backend 사용자 매핑
- Secrets Manager: DB credential, runtime config, 외부 서비스 설정
- RDS MariaDB: 업무 데이터 저장

완료 기준:

- 각 AWS dependency에 대해 정상 경로와 실패 경로를 문서화해야 한다.
- AccessDenied, queue mismatch, missing object, DB connection timeout 같은 장애 증상별 점검 지점이 있어야 한다.
- frontend가 직접 AWS credential을 다루지 않고 backend-controlled API 흐름을 거치도록 설명해야 한다.

### 2.4 Runtime configuration and secret handling

정리 대상:

- Spring datasource URL/username/password
- Cognito User Pool/App Client/JWKS URL
- S3 bucket name
- SQS queue URL
- Bedrock/OpenSearch runtime config
- AWS region and service endpoint config

운영 기준:

- secret value는 repository에 저장하지 않는다.
- 문서와 로그에는 token, password, account-specific secret 값을 기록하지 않는다.
- 검증 시에는 secret value가 아니라 key 존재 여부와 sync 상태만 확인한다.

완료 기준:

- example config와 real secret을 분리한다.
- `application-prod.properties` 또는 equivalent runtime contract가 있어야 한다.
- Kubernetes Secret/ExternalSecret/Secrets Manager 중 어떤 경로로 주입되는지 설명 가능해야 한다.

### 2.5 Backend verification

검증 항목:

- Maven compile/test
- Docker image build
- runtime container startup
- `/actuator/health`
- DB migration/validate
- S3 upload smoke
- SQS log polling smoke
- protected API 401/200 boundary
- image tag consistency
- backend log inspection

완료 기준:

- GitHub Actions 또는 local script로 반복 가능한 검증 명령이 있어야 한다.
- 배포 완료 기준이 “workflow 성공”이 아니라 “runtime 상태 확인”으로 정리되어야 한다.

## 3. Core Scope: Cloud Infrastructure and Operations

### 3.1 Terraform infrastructure

정리 대상:

- VPC / subnet / route / security group
- EKS cluster / node group
- ECR repositories
- RDS MariaDB
- S3 buckets
- SQS queues
- Cognito
- IAM roles and policies
- Secrets Manager
- CloudFront / frontend hosting
- ArgoCD / Kubernetes bootstrap integration

운영 기준:

- Terraform fmt/validate/plan/apply 흐름을 분리한다.
- apply는 승인 기반으로만 실행한다.
- remote state backend를 사용한다.
- plan/apply 로그에 secret value나 과도한 민감 정보가 노출되지 않게 한다.
- destroy는 일반 검증 대상이 아니라 환경 종료나 비용 정리 시 별도 통제 대상으로 둔다.

### 3.2 GitHub Actions and deployment control

정리 대상:

- backend Maven verification
- backend Docker image build verification
- backend image publish to ECR
- analysis service image publish to ECR
- Terraform validation and optional plan
- approval-based Terraform apply
- frontend build/deploy는 E2E surface 유지 범위로만 관리

완료 기준:

- PR 검증 단계와 운영 반영 단계가 분리되어야 한다.
- AWS 접근은 long-lived access key보다 OIDC role assume 구조를 우선한다.
- image publish workflow는 ECR push와 manifest image tag update를 추적해야 한다.

### 3.3 Kubernetes and GitOps runtime

정리 대상:

- backend Deployment/Service
- analysis service Deployment/Service
- runtime Secrets
- ExternalSecret or built-in Kubernetes Secret contract
- ArgoCD Application and sync path
- rollout status and service endpoint

완료 기준:

- manifest image tag와 실제 deployment image가 일치해야 한다.
- rollout status가 성공해야 한다.
- service endpoint가 비어 있지 않아야 한다.
- pod log에서 DB, Secret, S3, SQS, Bedrock/OpenSearch 오류를 확인할 수 있어야 한다.

## 4. Non-Core Scope

다음은 필요 최소한으로만 유지한다.

### 4.1 Frontend

Frontend는 사용자 E2E 흐름을 확인하기 위한 client surface다.

- frontend 전체 개발을 본인 핵심 기여로 설명하지 않는다.
- 화면 기능 추가를 고도화 핵심 작업으로 삼지 않는다.
- 필요한 경우 API smoke와 브라우저 E2E 검증을 위한 최소 수정만 수행한다.

### 4.2 AI generation quality

AI가 생성하는 Terraform 코드의 품질 개선은 핵심 범위가 아니다.

- prompt engineering 고도화를 중심 주제로 삼지 않는다.
- Claude Code, Cursor, Codex 같은 AI 개발 도구와 경쟁하는 프로젝트로 설명하지 않는다.
- 생성 결과는 운영 적용 코드가 아니라 검토 가능한 IaC 초안으로 설명한다.

### 4.3 Platform productization

다음 방향으로 확장하지 않는다.

- Terraform 승인 플랫폼
- 환경 신청 포털
- AWS Service Catalog/Backstage/env0 대체 서비스
- 운영 로그 분석 리포트 서비스
- 샌드박스 lifecycle 관리 서비스

## 5. Public repository import priority

private 작업물에서 공개 저장소로 이전할 우선순위는 다음이다.

### Priority 1: Documentation baseline

- `PROJECT_DIRECTION.md`
- `README.md`
- architecture/deployment/validation/runbook/interview guide
- backend-infra scope
- migration plan

### Priority 2: Backend source and verification

- Spring Boot backend source
- backend Dockerfile
- backend profile config without secrets
- Flyway migrations
- backend tests
- backend smoke scripts
- Maven and Docker GitHub Actions

### Priority 3: Cloud infrastructure

- Terraform modules and env structure
- GitHub Actions Terraform validation/apply workflow
- Kubernetes manifests
- External Secrets or Secret contract manifests
- ECR/image publish workflows

### Priority 4: Evidence and operational references

- sanitized command examples
- smoke test output templates
- deployment verification checklist
- runbook examples

## 6. Completion definition

이 프로젝트의 고도화 완료 기준은 다음이다.

```text
코드가 존재한다 -> 빌드된다 -> 이미지가 만들어진다 -> 인프라 정의가 검증된다 -> runtime config가 분리된다 -> 배포 후 상태를 확인할 수 있다 -> 장애 상황별 점검 순서가 문서화된다.
```

따라서 최종 설명은 다음처럼 한다.

```text
Terraformers 팀 프로젝트의 서비스 기능을 유지하되, 후속 작업에서 Spring Boot backend, RDB/Flyway, S3/SQS 연동, Secret 관리, Terraform 인프라, GitHub Actions 배포 흐름, smoke test와 runbook을 정리해 백엔드·클라우드 인프라 중심의 운영환경 고도화를 수행했습니다.
```
