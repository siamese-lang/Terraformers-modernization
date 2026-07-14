# Interview Guide

## 1. 프로젝트 한 줄 설명

```text
Terraformers는 AWS Cloud School 팀 프로젝트로 만든 AI 기반 IaC 초안 생성 웹서비스를 기반으로, 후속 작업에서 컨테이너 실행 구조, RDB/Flyway, S3/SQS 연동, Secret 분리, GitHub Actions 배포 흐름, smoke test와 runbook을 정리한 클라우드 웹서비스 운영환경 고도화 프로젝트입니다.
```

더 짧게 말하면 다음과 같다.

```text
팀 프로젝트 Terraformers를 컨테이너 기반 클라우드 웹서비스로 설명할 수 있도록 배포·운영환경을 고도화한 프로젝트입니다.
```

## 2. 프로젝트 제목

포트폴리오 제목은 다음을 사용한다.

```text
Terraformers: 컨테이너 기반 웹서비스 배포·운영환경 고도화
```

보조 제목은 다음을 사용할 수 있다.

```text
Terraformers Cloud-Native Runtime Modernization
```

## 3. 프로젝트 배경

팀 프로젝트 당시에는 제한된 기간 안에서 기능 구현과 시연 완성이 우선이었다.

그러나 포트폴리오와 면접에서 실제 서비스처럼 설명하려면 다음 항목이 부족했다.

- 배포 후 상태 확인 절차
- runtime config와 Secret 분리
- DB schema 정합성 관리
- Docker image build/publish 기준
- GitHub Actions 검증 흐름
- S3/SQS/RDS 외부 의존성 연동 검증
- 장애 상황별 점검 순서
- README와 운영 문서

후속 고도화 작업에서는 이 부족한 부분을 정리했다.

## 4. 팀 프로젝트 당시 기여

팀 프로젝트 당시 기여는 다음 범위로 설명한다.

- 백엔드 일부 기능 구현
- 컨테이너/클라우드 배포 흐름 점검
- S3, 인증, 배포, 결과 조회 등 서비스 흐름 일부 검증
- 팀 프로젝트 전체 산출물 완성에 참여

주의할 점은 다음이다.

- 프론트엔드 전체 개발을 본인 기여로 설명하지 않는다.
- 전체 서비스를 혼자 만든 것처럼 말하지 않는다.
- AI 모델 성능 개선이나 생성 품질 고도화를 본인 핵심 기여로 말하지 않는다.

## 5. 후속 고도화 기여

후속 고도화 기여는 다음 범위로 설명한다.

- 기존 팀 프로젝트 산출물 재점검
- RDB 중심 데이터 구조 및 schema migration 정리
- Docker 기반 backend/analysis service 실행 환경 정리
- runtime config와 Secret 분리
- S3/SQS/RDS/Secrets Manager 등 외부 의존성 연결 검증
- Terraform/GitHub Actions 기반 인프라·배포 흐름 정리
- ECR image build/publish 및 manifest image tag 반영 흐름 정리
- 배포 후 smoke test와 E2E 검증 절차 문서화
- 장애 상황별 점검 runbook 작성
- 포트폴리오 제출용 README, architecture, deployment, validation, runbook 문서 정리

## 6. 면접에서 강조할 핵심 역량

### 6.1 컨테이너 기반 운영환경 이해

설명 포인트는 다음이다.

```text
Spring Boot backend와 Python analysis service를 각각 독립적인 container image로 보고, source merge 이후 image build, ECR push, manifest image tag update, ArgoCD sync, rollout status 확인까지를 배포 완료 기준으로 정리했습니다.
```

### 6.2 RDB/Flyway 기반 schema 정합성

설명 포인트는 다음이다.

```text
사용자, 프로젝트, 파일, 댓글처럼 관계가 있는 업무 데이터는 RDB가 더 적합하다고 보고, RDS MariaDB 중심으로 정리했습니다. 운영에서는 엔티티와 DB schema가 어긋나면 장애로 이어질 수 있으므로 Flyway migration과 Hibernate validate로 schema drift를 조기에 확인하도록 했습니다.
```

### 6.3 Secret/runtime config 분리

설명 포인트는 다음이다.

```text
DB password, Cognito 설정, S3/SQS/Bedrock/OpenSearch runtime config를 코드에 직접 두지 않고 Secrets Manager와 External Secrets 기반으로 주입하는 구조로 정리했습니다. 검증할 때도 secret value를 출력하지 않고 key 존재 여부와 sync 상태만 확인하도록 문서화했습니다.
```

### 6.4 배포 후 검증

설명 포인트는 다음이다.

```text
GitHub Actions 성공만으로 배포 완료라고 보지 않았습니다. ECR image tag, Kubernetes manifest, 실제 deployment image가 일치하는지 확인하고, rollout status, health check, API smoke, E2E flow, log inspection까지 확인하는 절차를 정리했습니다.
```

### 6.5 장애 대응 문서화

설명 포인트는 다음이다.

```text
DB 연결 실패, Secret 누락, S3 권한 오류, SQS 메시지 처리 실패, worker 장애, image tag 불일치, schema migration 실패, CloudFront API routing 문제를 runbook으로 나누어 계층별로 확인할 수 있게 했습니다.
```

## 7. AI 기능에 대한 방어 답변

### 질문: 이 프로젝트는 결국 AI로 Terraform 코드를 생성하는 서비스 아닌가요?

답변 방향:

```text
서비스 기능만 보면 아키텍처 이미지를 분석해 Terraform 코드 초안을 생성하는 서비스가 맞습니다. 다만 제가 포트폴리오에서 강조하려는 부분은 AI 생성 품질이 아닙니다. 팀 프로젝트 당시에는 기능 완성과 시연이 중심이었고, 후속 작업에서는 이 서비스를 실제 클라우드 웹서비스처럼 설명하기 위해 backend runtime, Python analysis service, RDB, S3, SQS, Secret, CI/CD, 배포 후 검증, runbook을 정리했습니다.
```

### 질문: Terraform 코드를 생성한다면 실제 운영에 바로 적용할 수 있나요?

답변 방향:

```text
아니요. AI가 생성한 Terraform 코드는 바로 운영에 적용하는 코드가 아니라 검토 가능한 초안으로 설명합니다. 실제 인프라 변경은 별도의 검토와 승인 기반 Terraform apply workflow를 통해 통제되어야 한다고 보았습니다. 그래서 이 프로젝트에서도 AI 생성 기능 자체보다 배포와 운영 통제 흐름을 강조합니다.
```

### 질문: Claude Code, Cursor 같은 AI 개발 도구와 뭐가 다른가요?

답변 방향:

```text
그런 개발 도구와 경쟁하는 프로젝트로 설명하지 않습니다. Terraformers는 팀 프로젝트 당시 만든 웹서비스이고, 이번 후속 작업은 코드 생성 도구를 고도화하는 것이 아니라 기존 팀 프로젝트 산출물을 컨테이너 기반 클라우드 웹서비스 운영환경으로 정리하는 데 목적이 있습니다.
```

### 질문: AWS Service Catalog나 Backstage 같은 플랫폼을 만든 건가요?

답변 방향:

```text
아닙니다. 이 프로젝트는 환경 신청 포털이나 플랫폼 엔지니어링 도구를 만드는 것이 아닙니다. 원래 팀 프로젝트인 Terraformers의 서비스 흐름을 유지하되, backend, analysis worker, RDB, S3, SQS, Secret, CI/CD, smoke test, runbook을 정리해 운영환경 고도화 경험으로 설명하는 프로젝트입니다.
```

## 8. 다계층 업무시스템 운영 프로젝트와의 차별점

별도 개인 프로젝트인 **AWS EC2 기반 다계층 업무시스템 운영환경 구축 및 장애·복구 검증**과 비교하면 다음과 같다.

| 구분 | 다계층 업무시스템 운영 프로젝트 | Terraformers 운영환경 고도화 |
|---|---|---|
| 중심 환경 | VM 기반 WEB/WAS/DB/NFS | 컨테이너 기반 클라우드 웹서비스 |
| 주요 역량 | 인프라 운영, 장애·복구, 로그/지표 분석 | 배포·운영환경, CI/CD, cloud-managed service 연동 |
| runtime | EC2, Nginx, Spring Boot, PostgreSQL, NFS | Spring Boot backend, Python analysis service, EKS/container runtime |
| 데이터/외부 의존성 | DB, 파일 저장소, 백업/복구 | RDS, S3, SQS, Secrets Manager, Cognito, Bedrock/OpenSearch |
| 검증 관점 | 장애 재현, 성능 저하, 복구 검증 | image tag consistency, smoke/E2E, Secret sync, schema validation |
| 문서화 | 장애·복구 runbook | 배포·검증·runtime config·장애 runbook |

요약하면 다음과 같다.

```text
다계층 업무시스템 운영 프로젝트는 VM 기반 인프라 운영과 장애 복구 역량을 보여 주고, Terraformers 운영환경 고도화는 컨테이너 기반 클라우드 웹서비스의 배포·운영 역량을 보여 줍니다.
```

## 9. 자기소개서·면접 활용 문장

### 짧은 버전

```text
팀 프로젝트 Terraformers는 기능 완성과 시연에 집중한 프로젝트였지만, 후속 작업에서는 이를 실제 서비스처럼 설명할 수 있도록 컨테이너 실행 구조, RDB/Flyway, S3/SQS 연동, Secret 분리, GitHub Actions 배포 흐름, smoke test와 runbook을 정리했습니다.
```

### 긴 버전

```text
AWS Cloud School 팀 프로젝트에서는 아키텍처 이미지를 업로드하면 AI 분석을 통해 Terraform 코드 초안을 생성하는 웹서비스를 만들었습니다. 당시에는 제한된 기간 안에서 기능 구현과 시연 완성이 우선이었기 때문에, 배포 이후 상태 확인이나 Secret 관리, DB schema 정합성, image tag 검증, 장애 시 점검 절차가 충분히 정리되어 있지 않았습니다. 이후 이 산출물을 다시 점검하며 Spring Boot backend와 Python analysis service의 컨테이너 실행 구조, RDS/Flyway 기반 데이터 관리, S3/SQS 연동, Secrets Manager/External Secrets 기반 runtime config 분리, GitHub Actions와 Terraform 기반 배포 흐름, smoke test와 runbook을 정리했습니다. 이 과정을 통해 기능 구현 이후에도 서비스가 실제 실행 환경에서 정상 반영됐는지 확인하는 운영 관점의 중요성을 체감했습니다.
```

## 10. 피해야 할 표현

다음 표현은 피한다.

- “제가 Terraformers 전체를 개발했습니다.”
- “AI Terraform 생성 품질을 고도화했습니다.”
- “운영 플랫폼을 만들었습니다.”
- “Terraform 자동 승인/검증 시스템을 만들었습니다.”
- “프론트엔드까지 모두 구현했습니다.”
- “실제 운영 수준으로 완성했습니다.”

대신 다음 표현을 사용한다.

- “팀 프로젝트 산출물을 기반으로 후속 고도화를 수행했습니다.”
- “포트폴리오 제출 가능한 수준으로 운영환경과 문서를 정리했습니다.”
- “컨테이너 기반 클라우드 웹서비스 배포·검증 흐름을 정리했습니다.”
- “배포 후 상태 확인과 장애 점검 절차를 문서화했습니다.”
- “AI 생성 코드는 운영 적용 전 검토 가능한 초안으로 설명했습니다.”
