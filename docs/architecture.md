# Architecture

## 1. 목적

이 문서는 Terraformers 운영환경 고도화 프로젝트의 시스템 구조와 구성요소 책임을 설명한다.

설명의 중심은 AI 생성 품질이 아니라, **Spring Boot backend, Python analysis service, RDB, S3, SQS, Secret, container runtime, CI/CD가 어떻게 연결되어 운영 가능한 웹서비스 흐름을 만드는가**이다.

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
  |-- RDS MariaDB
  |-- Amazon S3
  |-- Amazon SQS
  |-- Secrets Manager / External Secrets
  |
  | HTTP /analyze
  v
Python Bedrock Analysis Service
  |-- Amazon Bedrock
  |-- OpenSearch / AOSS
  |-- SQS result publish
```

## 3. Component Responsibilities

### 3.1 Frontend

Frontend는 React 기반 SPA로 설명한다.

주요 책임은 다음이다.

- 사용자 로그인/인증 흐름 진입
- 이미지 업로드 화면 제공
- AI 분석 진행 로그 표시
- Terraform 코드 초안 조회
- 프로젝트 tree, 공개 프로젝트, 댓글 화면 제공
- backend API 호출 시 access token 전달

주의할 점은, 이 프로젝트에서 frontend 개발을 본인 핵심 기여로 과장하지 않는다는 것이다. 포트폴리오 설명에서는 frontend를 서비스 흐름을 구성하는 클라이언트로만 설명한다.

### 3.2 Spring Boot Backend

Backend는 Terraformers 서비스의 API와 업무 데이터 처리를 담당한다.

주요 책임은 다음이다.

- Cognito access token 검증
- 사용자 identity와 RDB user mapping
- 프로젝트, 파일, 공개 전환, 댓글 API 제공
- RDB 기반 metadata 저장
- S3 기반 업로드 이미지 및 생성 파일 저장
- Python analysis service 호출
- SQS 기반 AI/Terraform 진행 로그 및 결과 조회
- runtime config와 secret을 환경 변수 또는 Kubernetes Secret contract로 주입받아 실행

운영 관점에서 backend의 핵심은 다음이다.

- DB schema와 entity 불일치가 발생하면 startup에서 조기에 실패하도록 한다.
- S3 객체 저장과 RDB metadata 저장의 책임을 분리한다.
- SQS queue URL과 projectId 흐름을 검증하여 잘못된 polling이나 결과 혼선을 줄인다.
- 배포 후 health check, rollout status, application log를 통해 runtime 상태를 확인한다.

### 3.3 Python Bedrock Analysis Service

Python analysis service는 업로드된 아키텍처 이미지를 분석하고 Terraform 코드 초안을 생성하는 별도 runtime component다.

주요 책임은 다음이다.

- backend의 `/analyze` 요청 수신
- S3 bucket/key 기준 업로드 이미지 조회
- 이미지 media type 확인
- Bedrock model 호출
- OpenSearch/AOSS reference 검색
- Terraform 코드 초안 생성
- SQS에 진행 로그와 최종 결과 publish

운영 관점에서 이 서비스는 backend와 독립적으로 image build, deploy, rollout, log inspection이 가능해야 한다.

### 3.4 RDS MariaDB

RDS MariaDB는 관계형 업무 데이터의 source of truth로 둔다.

대표 데이터는 다음이다.

- users
- projects
- project_files
- boards
- comments
- reactions
- terraform run/log metadata

RDB를 사용하는 이유는 다음이다.

- 사용자, 프로젝트, 파일, 댓글 사이의 관계를 명확하게 표현할 수 있다.
- transaction과 referential integrity를 활용할 수 있다.
- SQL 기반 점검이 가능해 운영 중 원인 분석이 쉽다.
- Flyway migration으로 schema 변경 이력을 코드로 추적할 수 있다.
- Hibernate validate로 entity와 schema의 불일치를 startup 시점에 감지할 수 있다.

### 3.5 Amazon S3

S3는 객체 파일 저장소다.

저장 대상은 다음이다.

- 업로드된 아키텍처 이미지 원본
- 생성된 Terraform 코드 파일
- Terraform state 또는 실행 산출물

운영 원칙은 다음이다.

- 실제 파일 content는 S3에 저장한다.
- RDB에는 object key, owner, projectId, file metadata, 상태값 등 관계형 metadata를 저장한다.
- S3 저장 성공과 RDB 저장 성공이 어긋날 수 있으므로 보상 처리 또는 점검 절차가 필요하다.

### 3.6 Amazon SQS

SQS는 긴 처리 흐름의 로그와 결과를 전달하는 비동기 채널이다.

사용 이유는 다음이다.

- AI 분석이나 Terraform 실행은 짧은 HTTP 요청으로 끝나지 않을 수 있다.
- frontend가 긴 처리 중에도 진행 상태를 확인할 수 있다.
- backend와 analysis service 사이의 처리 결과 전달을 느슨하게 연결할 수 있다.
- projectId 기준으로 현재 프로젝트에 해당하는 결과를 구분할 수 있다.

운영 점검 기준은 다음이다.

- queue URL이 runtime config와 일치하는지 확인한다.
- 메시지가 publish되는지 확인한다.
- projectId가 누락되거나 잘못된 결과가 섞이지 않는지 확인한다.
- DLQ 또는 실패 처리 정책은 운영 단계에서 별도 보강 대상으로 둔다.

### 3.7 Secrets Manager / External Secrets

민감 정보와 runtime config는 코드나 manifest에 직접 기록하지 않는다.

권장 흐름은 다음이다.

```text
AWS Secrets Manager
  -> External Secrets Operator
  -> Kubernetes Secret
  -> backend / analysis service environment variables
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

### 3.8 Container Runtime / EKS / ArgoCD

backend와 Python analysis service는 container image로 빌드하고, ECR에 push한 뒤 Kubernetes manifest image tag를 기준으로 배포한다.

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
5. backend가 Python analysis service에 bucket/key/projectId/queueUrl을 전달한다.
6. Python analysis service가 S3에서 이미지를 읽는다.
7. Python analysis service가 Bedrock/OpenSearch를 활용해 Terraform 코드 초안을 생성한다.
8. Python analysis service가 SQS에 진행 로그와 최종 결과를 publish한다.
9. frontend가 backend를 통해 SQS log/result를 polling한다.
10. backend가 생성 결과 metadata를 RDB에 반영하고 content는 S3에 저장한다.
```

### 4.3 Project Tree and Public Project Flow

```text
1. 사용자가 프로젝트 상세 또는 tree를 요청한다.
2. backend가 사용자 권한과 프로젝트 접근 가능성을 확인한다.
3. backend가 RDB의 project_files를 조회한다.
4. backend가 파일 tree를 구성해 반환한다.
5. 사용자가 visibility를 PUBLIC으로 전환하면 공개 목록에 노출한다.
6. 댓글은 board/comment/reaction 관계를 기준으로 RDB에 저장한다.
```

## 5. Operational Control Points

면접과 포트폴리오에서는 다음 통제 포인트를 중심으로 설명한다.

- AI가 생성한 Terraform code는 운영 적용 전 검토 가능한 초안이다.
- 실제 인프라 변경은 승인 기반 Terraform apply workflow로 통제한다.
- 긴 AI/Terraform 처리 흐름은 SQS log/result channel로 상태를 전달한다.
- Runtime secret은 Secrets Manager와 External Secrets를 통해 주입한다.
- 배포 후에는 rollout status, image tag consistency, health check, API smoke test를 확인한다.
- DB schema 변경은 Flyway migration과 Hibernate validate로 관리한다.
