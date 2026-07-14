# Terraformers 운영환경 고도화 프로젝트 방향

## 1. 프로젝트 정체성

이 저장소는 AWS Cloud School 팀 프로젝트 **Terraformers**를 기반으로 한 후속 고도화 작업을 정리하기 위한 공개 포트폴리오 저장소다.

Terraformers는 사용자가 AWS 아키텍처 이미지를 업로드하면 AI 분석 결과를 바탕으로 Terraform 코드 초안을 생성하고, 프로젝트·파일·결과·로그·댓글 등 관련 데이터를 관리하는 웹서비스다.

이번 작업의 목적은 Terraformers를 완전히 다른 개인 프로젝트로 바꾸는 것이 아니다. 팀 프로젝트 당시 제한된 기간 안에서 기능 완성과 시연에 집중했던 산출물을 현재 기준에서 포트폴리오 제출 가능한 수준의 **백엔드 중심·클라우드 인프라 운영환경 고도화 완료 버전**으로 정리하는 것이다.

최종 설명 제목은 다음 중 하나를 사용한다.

- Terraformers: 백엔드·클라우드 인프라 운영환경 고도화
- Terraformers Backend & Cloud Infrastructure Modernization
- Terraformers Cloud-Native Runtime Modernization

## 2. 프로젝트 설명의 중심

이 프로젝트의 중심은 AI 생성 품질 개선이 아니다. 또한 frontend 개발 역량을 보여 주는 프로젝트도 아니다.

서비스 기능은 다음 수준으로 설명한다.

- 사용자가 아키텍처 이미지를 업로드한다.
- Spring Boot backend가 analysis job lifecycle을 소유한다.
- backend가 S3 source object read, reference retrieval, Bedrock generation, S3 result object write, SQS progress publish를 adapter boundary로 분리한다.
- backend가 프로젝트, 파일, 결과, 로그, 댓글 등 서비스 데이터를 관리한다.
- RDB, S3, SQS, Secrets Manager 등 AWS 의존성을 통해 실제 클라우드 서비스 흐름을 구성한다.

포트폴리오에서 강조할 중심은 다음이다.

### Backend development

- Spring Boot backend API와 domain 흐름 정리
- 사용자, 프로젝트, 파일, 댓글, analysis job, 결과 object key 등 업무 데이터 모델 정리
- RDB 중심 persistence 구조와 schema migration 정리
- S3 object 저장과 RDB metadata 저장 책임 분리
- SQS 기반 처리 로그와 결과 전달 흐름 정리
- Cognito token 검증과 backend user mapping 흐름 정리
- runtime config와 Secret 주입 방식 정리
- startup, health check, dependency failure 진단 기준 정리
- backend build/test/smoke test 기준 정리

### Cloud infrastructure and operations

- Terraform 기반 AWS 인프라 구성 정리
- EKS, ECR, RDS, S3, SQS, Cognito, IAM, Secrets Manager, CloudFront 구성 정리
- GitHub Actions OIDC 기반 AWS 접근 구조 정리
- 승인 기반 Terraform plan/apply 흐름 정리
- backend image build와 ECR publish 흐름 정리
- Kubernetes manifest image tag와 runtime deployment 일치성 검증
- External Secrets 또는 Kubernetes Secret 기반 runtime config 전달 구조 정리
- 배포 후 rollout, health, API smoke, log inspection 절차 정리
- 장애 상황별 runbook 작성

### Frontend stabilization

프론트엔드는 핵심 기여로 과장하지 않는다. 다만 backend/cloud 고도화 결과를 실제 서비스 흐름으로 시연하려면 기존 화면의 막힌 흐름은 최소한으로 복구해야 한다.

프론트 작업은 다음 범위로 제한한다.

- 회원가입 또는 로그인 후 검은 화면으로 막히는 문제 확인 및 수정
- 메인 화면의 아이콘/버튼이 동작하지 않거나 잘못된 route로 이동하는 문제 정리
- upload, analysis job 생성, result preview/object key 확인, project detail 조회 흐름 연결
- API base URL, Cognito config, Authorization header, CORS/CloudFront routing 불일치 점검
- 브라우저 smoke flow를 막는 runtime error 제거

프론트 작업은 새 기능 개발이나 UI 전면 개편이 아니라, 기존 팀 프로젝트 화면이 backend 운영환경 고도화 결과를 보여 줄 수 있도록 안정화하는 작업이다.

## 3. 팀 프로젝트 당시 기여와 후속 고도화 기여 구분

### 팀 프로젝트 당시 기여

팀 프로젝트 당시 기여는 다음 범위로 설명한다.

- 백엔드 일부 기능 구현
- 컨테이너/클라우드 배포 흐름 점검
- S3, 인증, 배포, 결과 조회 등 서비스 흐름 일부 검증
- 팀 프로젝트 전체 산출물 완성에 참여

프론트엔드 전체 개발, AI 모델 품질 개선, 전체 서비스 단독 구현으로 설명하지 않는다.

### 후속 고도화 기여

후속 고도화 기여는 다음 범위로 설명한다.

- 기존 팀 프로젝트 산출물 재점검
- backend domain/API/persistence 구조 정리
- RDB 중심 데이터 구조 및 schema migration 정리
- S3/SQS/RDS/Secrets Manager 등 backend 외부 의존성 연결 검증
- backend-owned analysis orchestration 구조 정리
- Docker 기반 backend 실행 환경 정리
- Terraform 기반 AWS 인프라 구성 정리
- runtime contract와 Secret 분리
- 배포 후 smoke test와 E2E 검증 절차 문서화
- 장애 상황별 점검 runbook 작성
- 기존 프론트엔드 화면의 차단 오류를 서비스 시연 가능한 수준으로 안정화
- 포트폴리오 제출용 README, architecture, deployment, validation, runbook 문서 정리

## 4. 반드시 피해야 할 방향

이 프로젝트는 다음 방향으로 설명하거나 확장하지 않는다.

1. Terraformers를 완전히 새로운 개인 프로젝트로 바꾸지 않는다.
2. 완성도 낮은 프로젝트 개수를 늘리기 위한 파생 프로젝트로 만들지 않는다.
3. “AI로 Terraform 코드를 더 잘 생성하는 서비스”를 핵심 고도화 주제로 삼지 않는다.
4. Claude Code, Codex, Cursor 같은 AI 개발 도구와 경쟁하는 코드 생성·리팩토링 서비스로 만들지 않는다.
5. AWS Service Catalog, Backstage, env0 같은 서비스의 하위호환처럼 보이는 환경 신청 포털로 만들지 않는다.
6. Terraform plan 검증·승인 플랫폼으로 만들지 않는다.
7. 운영 로그 분석 리포트 서비스, 파일 처리 서비스, 샌드박스 lifecycle 서비스 등으로 주제를 바꾸지 않는다.
8. Terraform 자체를 프로젝트 주제로 삼지 않는다.
9. 프론트엔드 개발을 본인 핵심 기여로 과장하지 않는다.
10. 프론트엔드 전면 재개발이나 디자인 프로젝트로 범위를 키우지 않는다.
11. 전체 서비스를 혼자 만든 것처럼 설명하지 않는다.
12. GitHub Actions나 배포 파이프라인이 실패 상태인데도 완료된 CI/CD로 설명하지 않는다.

## 5. 최종 산출물 기준

최종 정리본에는 다음 문서와 코드 범위가 있어야 한다.

### 문서

- `README.md`
  - 프로젝트 개요
  - 팀 프로젝트와 후속 고도화 구분
  - 본인 기여 범위
  - 백엔드·클라우드 인프라 중심 아키텍처 요약
  - 실행/배포/검증 방법
  - 면접에서 설명 가능한 핵심 포인트

- `docs/backend-infra-scope.md`
  - 백엔드 개발 범위
  - 클라우드 인프라 구축·관리 범위
  - 제외 범위
  - 코드 이전 우선순위

- `docs/migration-plan.md`
  - private 작업물에서 공개 저장소로 이전할 항목
  - 공개 저장소에 올리지 않을 항목
  - 민감정보 제거 기준
  - 단계별 이전 계획

- `docs/architecture.md`
  - frontend, Spring Boot backend, RDB, S3, SQS, Secret, container runtime, CI/CD 구성 설명

- `docs/deployment-runtime-contract.md`
  - Kubernetes ConfigMap/Secret contract
  - adapter switch
  - local/stub mode와 AWS adapter mode 구분

- `docs/validation.md`
  - backend local verification
  - runtime contract verification
  - API smoke test
  - image tag consistency
  - DB migration/schema validation
  - S3/SQS 연동 확인
  - 로그 확인

- `docs/runbook.md` 및 `docs/runbooks/*`
  - DB 연결 실패
  - Secret 누락
  - S3 source read failure
  - S3 result write failure
  - Bedrock timeout
  - OpenSearch query failure
  - SQS progress publish failure
  - 잘못된 image tag 배포
  - schema migration 실패
  - health check 실패

- `docs/frontend-stabilization-plan.md`
  - 프론트엔드 안정화 범위
  - 회원가입 검은 화면 점검
  - 메인 화면 dead control 점검
  - API/auth/runtime config mismatch 점검
  - 브라우저 smoke flow 기준

- `docs/interview-guide.md`
  - 프로젝트 한 줄 설명
  - 팀 프로젝트 당시 기여
  - 후속 고도화 기여
  - AI 기능에 대한 방어 답변
  - 운영환경 고도화의 의의
  - 다계층 업무시스템 운영 프로젝트와의 차별점

### 코드와 인프라

- backend Spring Boot source
- backend Dockerfile
- backend test/smoke script
- Flyway migration
- frontend source stabilization patch
- Terraform infrastructure/runtime contract code
- Kubernetes manifests 또는 GitOps manifests
- manual GitHub Actions workflows
- cloud/runtime config examples without secret values

## 6. 다른 개인 운영 프로젝트와의 차별점

별도 개인 프로젝트인 **AWS EC2 기반 다계층 업무시스템 운영환경 구축 및 장애·복구 검증**은 VM 기반 WEB/WAS/DB/NFS 운영환경, 장애·성능·복구 검증, 로그와 지표 기반 원인 분석, 백업/복구 runbook을 보여 주는 프로젝트다.

Terraformers 고도화 프로젝트는 그와 달리 다음 역량을 보여 주는 프로젝트로 고정한다.

- Spring Boot backend 개발 및 운영 구조 정리
- RDB/Flyway 기반 schema 관리
- AWS 관리형 서비스 연동
- RDS, S3, SQS, Secrets Manager 기반 runtime 구성
- EKS/ECR/Terraform/GitHub Actions 기반 클라우드 인프라 구축·관리
- 배포 후 smoke test와 E2E 검증
- 클라우드 네이티브 서비스 운영 문서화
- 기존 프론트 화면을 이용한 최소 E2E 시연 안정화

정리하면 다음과 같다.

- 다계층 업무시스템 운영 프로젝트: VM 기반 인프라 운영·장애 복구 역량
- Terraformers 운영환경 고도화 프로젝트: 백엔드 개발과 컨테이너 기반 클라우드 인프라 구축·관리 역량

## 7. 핵심 설명 문장

면접과 포트폴리오에서는 다음 메시지를 기준으로 설명한다.

> 팀 프로젝트에서는 기능 완성과 시연에 집중했지만, 이후 실제 서비스로 설명하려면 백엔드 구조, DB 스키마 정합성, 외부 AWS 의존성 연결, Secret 관리, 인프라 변경 통제, 배포 후 상태 확인, 장애 시 점검 절차가 필요하다고 판단했습니다. 그래서 기존 Terraformers 산출물을 기반으로 Spring Boot backend, RDB/Flyway, S3/SQS 연동, Secrets Manager/External Secrets, Terraform 인프라, smoke test와 runbook을 정리해 백엔드·클라우드 인프라 중심의 운영환경 고도화를 수행했습니다. 프론트엔드는 핵심 기여로 과장하지 않고, 회원가입·메인 화면·분석 결과 확인처럼 E2E 시연을 막는 문제를 안정화하는 범위에서 다뤘습니다.
