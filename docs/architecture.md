# Architecture

## 1. 목적

이 문서는 Terraformers 운영환경 고도화 프로젝트의 시스템 구조와 구성요소 책임을 설명한다.

현재 설명의 중심은 **Spring Boot backend가 서비스 API, RDB 상태, S3/SQS/Bedrock/OpenSearch 연동, runtime config, 배포 후 검증 책임을 소유하는 구조**다.

기존 팀 프로젝트에는 Python analysis service가 별도 runtime으로 존재했지만, 공개 포트폴리오의 기본 목표는 backend 개발과 cloud infrastructure 구축·관리다. 따라서 Python service는 기본 runtime이 아니라 legacy reference로 둔다.

## 2. High-level Architecture

```text
User Browser
  |
  | HTTPS
  v
CloudFront
  |-- S3 frontend bucket
  |-- /api/* backend origin
  v
React Frontend
  |
  | Cognito auth flow
  | Authorization: Bearer <access-token>
  v
Spring Boot Backend
  |-- RDS MariaDB: users/projects/files/comments/reactions/analysis_jobs
  |-- Amazon S3: uploaded images and generated files
  |-- Amazon SQS: progress and result messages
  |-- Amazon Bedrock: image analysis and Terraform draft generation
  |-- OpenSearch / AOSS: reference retrieval
  |-- Secrets Manager / External Secrets: runtime config delivery
```

## 3. Component Responsibilities

### 3.1 Frontend

Frontend는 React 기반 SPA로 설명한다.

주요 책임은 다음이다.

- 사용자 로그인/인증 흐름 진입
- 이미지 업로드 화면 제공
- 분석 진행 로그 표시
- Terraform 코드 초안 조회
- 프로젝트 tree, 공개 프로젝트, 댓글 화면 제공
- backend API 호출 시 access token 전달

이 프로젝트에서 frontend 개발을 본인 핵심 기여로 과장하지 않는다. Frontend는 backend/API/E2E 흐름을 확인하기 위한 client surface로 설명한다.

### 3.2 Spring Boot Backend

Backend는 Terraformers 서비스의 API, 업무 데이터, 분석 job lifecycle, 외부 AWS dependency 연동을 담당한다.

주요 책임은 다음이다.

- Cognito access token 검증
- 사용자 identity와 RDB user mapping
- 프로젝트, 파일, 공개 전환, 댓글 API 제공
- RDB 기반 metadata 저장
- S3 기반 업로드 이미지 및 생성 파일 저장
- analysis job 생성과 상태 관리
- Bedrock/OpenSearch 기반 분석 orchestration
- SQS 기반 진행 로그 및 결과 발행/조회
- runtime config와 secret을 환경 변수 또는 Kubernetes Secret contract로 주입받아 실행

운영 관점에서 backend의 핵심은 다음이다.

- DB schema와 entity 불일치가 발생하면 startup에서 조기에 실패하도록 한다.
- S3 객체 저장과 RDB metadata 저장의 책임을 분리한다.
- 긴 분석 흐름은 `analysis_jobs` 상태로 추적한다.
- Bedrock/OpenSearch/SQS 장애를 backend adapter 실패로 분류한다.
- 배포 후 health check, rollout status, application log를 통해 runtime 상태를 확인한다.

### 3.3 Analysis orchestration

분석 기능은 기본적으로 backend가 소유한다.

```text
1. 사용자가 이미지를 업로드한다.
2. backend가 사용자/프로젝트/파일 context를 검증한다.
3. backend가 RDB에 analysis_jobs row를 생성한다.
4. backend가 S3 object metadata 또는 content를 조회한다.
5. backend가 Bedrock model을 호출한다.
6. backend가 OpenSearch/AOSS에서 reference pattern을 검색한다.
7. backend가 Terraform 코드 초안을 생성 또는 저장한다.
8. backend가 SQS에 진행 로그와 결과 메시지를 발행한다.
9. backend가 analysis_jobs status를 갱신한다.
10. frontend는 backend API를 통해 상태와 결과를 조회한다.
```

기존 Python service가 담당하던 S3 read, media type detection, Bedrock invoke, OpenSearch query, SQS publish는 Spring Boot backend adapter로 이전하는 것을 목표로 한다.

### 3.4 Python service status

Python service는 다음 조건이 충족될 때만 다시 core runtime으로 고려한다.

- Python 전용 이미지 처리 또는 ML library가 반드시 필요하다.
- 분석 workload가 backend와 독립적으로 scale-out되어야 한다는 측정 근거가 있다.
- 단순 HTTP side service가 아니라 queue-based worker architecture로 분리할 필요가 있다.

현재 기본 결정은 `docs/adr/0004-consolidate-analysis-orchestration-into-backend.md`를 따른다.

### 3.5 RDS MariaDB

RDS MariaDB는 관계형 업무 데이터의 source of truth로 둔다.

대표 데이터는 다음이다.

- users
- projects
- project_files
- boards
- comments
- reactions
- terraform run/log metadata
- analysis_jobs

RDB를 사용하는 이유는 다음이다.

- 사용자, 프로젝트, 파일, 댓글, 분석 job 사이의 관계를 명확하게 표현할 수 있다.
- transaction과 referential integrity를 활용할 수 있다.
- SQL 기반 점검이 가능해 운영 중 원인 분석이 쉽다.
- Flyway migration으로 schema 변경 이력을 코드로 추적할 수 있다.
- Hibernate validate로 entity와 schema의 불일치를 startup 시점에 감지할 수 있다.

### 3.6 Amazon S3

S3는 객체 파일 저장소다.

저장 대상은 다음이다.

- 업로드된 아키텍처 이미지 원본
- 생성된 Terraform 코드 파일
- Terraform state 또는 실행 산출물

운영 원칙은 다음이다.

- 실제 file content는 S3에 저장한다.
- RDB에는 object key, owner, projectId, file metadata, 상태값 등 관계형 metadata를 저장한다.
- S3 저장 성공과 RDB 저장 성공이 어긋날 수 있으므로 보상 처리 또는 점검 절차가 필요하다.

### 3.7 Amazon SQS

SQS는 긴 처리 흐름의 로그와 결과를 전달하는 비동기 채널이다.

사용 이유는 다음이다.

- AI 분석이나 Terraform 실행은 짧은 HTTP 요청으로 끝나지 않을 수 있다.
- frontend가 긴 처리 중에도 진행 상태를 확인할 수 있다.
- projectId 또는 analysisJobId 기준으로 현재 요청에 해당하는 결과를 구분할 수 있다.

운영 점검 기준은 다음이다.

- queue URL이 runtime config와 일치하는지 확인한다.
- 메시지가 publish되는지 확인한다.
- projectId/analysisJobId가 누락되거나 잘못된 결과가 섞이지 않는지 확인한다.
- DLQ 또는 실패 처리 정책은 운영 단계에서 별도 보강 대상으로 둔다.

### 3.8 Secrets Manager / External Secrets

민감 정보와 runtime config는 코드나 manifest에 직접 기록하지 않는다.

권장 흐름은 다음이다.

```text
AWS Secrets Manager
  -> External Secrets Operator
  -> Kubernetes Secret
  -> backend environment variables
```

관리 대상은 다음이다.

- datasource URL, username, password
- Cognito runtime config
- S3 bucket name
- SQS queue URL
- Bedrock/OpenSearch runtime config
- AWS role or runtime identity 관련 설정

점검 기준은 다음이다.

- Secret value를 직접 출력하지 않는다.
- key 존재 여부와 sync 상태를 확인한다.
- ExternalSecret `SecretSynced=True` 여부를 확인한다.
- 누락된 key가 있으면 pod startup error와 연결해 진단한다.

### 3.9 Container Runtime / EKS / ArgoCD

Backend는 container image로 빌드하고, ECR에 push한 뒤 Kubernetes manifest image tag를 기준으로 배포한다.

운영 관점의 핵심은 다음이다.

- source merge와 runtime 반영은 다르므로 image tag consistency를 확인한다.
- deployment image가 최신 manifest와 일치하는지 확인한다.
- ArgoCD sync 상태와 Kubernetes rollout status를 확인한다.
- pod log에서 DB, Secret, S3, SQS, Bedrock, OpenSearch 오류를 확인한다.

## 4. Main Request Flows

### 4.1 Login and API Call

```text
1. 사용자가 Cognito 기반 로그인 흐름을 수행한다.
2. frontend가 access token을 확보한다.
3. frontend가 backend API를 Authorization header와 함께 호출한다.
4. backend가 token을 검증한다.
5. backend가 Cognito identity를 RDB user와 매핑한다.
6. API logic이 RDB/S3/SQS 등 외부 의존성과 연동된다.
```

### 4.2 Image Upload and Terraform Draft Generation

```text
1. 사용자가 아키텍처 이미지를 업로드한다.
2. backend가 인증 사용자와 요청 값을 검증한다.
3. backend가 RDB에 project/file metadata를 생성한다.
4. backend가 이미지를 S3에 저장한다.
5. backend가 analysis job을 생성한다.
6. backend가 S3, Bedrock, OpenSearch adapter를 통해 분석을 수행한다.
7. backend가 SQS에 진행 로그와 최종 결과를 publish한다.
8. frontend가 backend API를 통해 log/result를 polling한다.
9. backend가 생성 결과 metadata를 RDB에 반영하고 content는 S3에 저장한다.
```

### 4.3 Project Tree and Public Project Flow

```text
1. backend가 projectId 기준으로 RDB metadata를 조회한다.
2. file metadata와 S3 object key를 조합해 project tree를 구성한다.
3. 공개 프로젝트 조회에서는 공개 상태와 댓글/반응 데이터를 함께 조회한다.
4. DB query, authorization, S3 key consistency를 함께 점검한다.
```

## 5. Architecture decision summary

```text
Python service is not a default runtime dependency.
Spring Boot backend owns analysis job lifecycle and AWS dependency orchestration.
Python can be revisited only when a measurable worker split or Python-specific processing requirement appears.
```
