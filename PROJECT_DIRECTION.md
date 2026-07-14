# Terraformers 운영환경 고도화 프로젝트 방향

## 1. 프로젝트 정체성

이 저장소는 AWS Cloud School 팀 프로젝트 **Terraformers**를 기반으로 한 후속 고도화 작업을 정리하기 위한 공개 포트폴리오 저장소다.

Terraformers는 사용자가 AWS 아키텍처 이미지를 업로드하면 AI 분석 결과를 바탕으로 Terraform 코드 초안을 생성하고, 프로젝트·파일·결과·로그·댓글 등 관련 데이터를 관리하는 웹서비스다.

이번 작업의 목적은 Terraformers를 완전히 다른 개인 프로젝트로 바꾸는 것이 아니다. 팀 프로젝트 당시 제한된 기간 안에서 기능 완성과 시연에 집중했던 산출물을 현재 기준에서 포트폴리오 제출 가능한 수준의 **컨테이너 기반 클라우드 웹서비스 운영환경 고도화 완료 버전**으로 정리하는 것이다.

최종 설명 제목은 다음 중 하나를 사용한다.

- Terraformers: 컨테이너 기반 웹서비스 배포·운영환경 고도화
- Terraformers Cloud-Native Runtime Modernization

## 2. 프로젝트 설명의 중심

이 프로젝트의 중심은 AI 생성 품질 개선이 아니다.

서비스 기능은 다음 수준으로 설명한다.

- 사용자가 아키텍처 이미지를 업로드한다.
- Python 분석 서비스가 Bedrock/OpenSearch를 활용해 분석 및 Terraform 코드 초안을 생성한다.
- Spring Boot backend가 프로젝트, 파일, 결과, 로그, 댓글 등 서비스 데이터를 관리한다.
- RDB, S3, SQS, Secrets Manager 등 AWS 의존성을 통해 실제 클라우드 서비스 흐름을 구성한다.

포트폴리오에서 강조할 중심은 다음이다.

- Spring Boot backend 운영환경 정리
- Python Bedrock analysis service 운영환경 정리
- Docker image build 및 ECR publish
- EKS 기반 컨테이너 runtime 구성
- RDS MariaDB 기반 업무 데이터 저장 구조
- Flyway migration과 Hibernate validate 기반 schema 정합성 관리
- S3 객체 저장과 RDB metadata 분리
- SQS 기반 AI/Terraform 처리 로그 및 결과 전달
- Secrets Manager와 External Secrets 기반 runtime config/secret 분리
- Terraform 기반 AWS 인프라 구성
- GitHub Actions 기반 검증, image publish, 승인형 Terraform apply
- 배포 후 smoke test, E2E 검증, image tag consistency 확인
- 장애 상황별 runbook 작성
- 포트폴리오 제출용 README와 문서 정리

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
- RDB 중심 데이터 구조 및 schema migration 정리
- Docker 기반 backend/analysis service 실행 환경 정리
- runtime config와 Secret 분리
- S3/SQS/RDS/Secrets Manager 등 외부 의존성 연결 검증
- Terraform/GitHub Actions 기반 인프라·배포 흐름 정리
- ECR image build/publish 및 manifest image tag 반영 흐름 정리
- 배포 후 smoke test와 E2E 검증 절차 문서화
- 장애 상황별 점검 runbook 작성
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
10. 전체 서비스를 혼자 만든 것처럼 설명하지 않는다.

## 5. 최종 산출물 기준

최종 정리본에는 다음 문서가 있어야 한다.

- `README.md`
  - 프로젝트 개요
  - 팀 프로젝트와 후속 고도화 구분
  - 본인 기여 범위
  - 아키텍처 요약
  - 실행/배포/검증 방법
  - 면접에서 설명 가능한 핵심 포인트

- `docs/architecture.md`
  - frontend, backend, Python analysis service, RDB, S3, SQS, Secret, container runtime, CI/CD 구성 설명

- `docs/deployment.md`
  - Docker image build
  - Terraform infrastructure
  - GitHub Actions workflow
  - runtime config/Secret 주입
  - 배포 순서

- `docs/validation.md`
  - 배포 후 smoke test
  - API 검증
  - image tag consistency
  - DB migration/schema validation
  - S3/SQS 연동 확인
  - 로그 확인

- `docs/runbook.md`
  - DB 연결 실패
  - Secret 누락
  - S3 권한 오류
  - SQS 메시지 처리 실패
  - worker 장애
  - 잘못된 image tag 배포
  - schema migration 실패
  - health check 실패

- `docs/interview-guide.md`
  - 프로젝트 한 줄 설명
  - 팀 프로젝트 당시 기여
  - 후속 고도화 기여
  - AI 기능에 대한 방어 답변
  - 운영환경 고도화의 의의
  - 다계층 업무시스템 운영 프로젝트와의 차별점

## 6. 다른 개인 운영 프로젝트와의 차별점

별도 개인 프로젝트인 **AWS EC2 기반 다계층 업무시스템 운영환경 구축 및 장애·복구 검증**은 VM 기반 WEB/WAS/DB/NFS 운영환경, 장애·성능·복구 검증, 로그와 지표 기반 원인 분석, 백업/복구 runbook을 보여 주는 프로젝트다.

Terraformers 고도화 프로젝트는 그와 달리 다음 역량을 보여 주는 프로젝트로 고정한다.

- 컨테이너 기반 웹서비스 운영
- Spring Boot backend와 Python analysis service 구성
- AWS 관리형 서비스 연동
- RDS, S3, SQS, Secrets Manager 기반 runtime 구성
- GitHub Actions, ECR, Terraform, ArgoCD 기반 배포 흐름
- 배포 후 smoke test와 E2E 검증
- 클라우드 네이티브 서비스 운영 문서화

정리하면 다음과 같다.

- 다계층 업무시스템 운영 프로젝트: VM 기반 인프라 운영·장애 복구 역량
- Terraformers 운영환경 고도화 프로젝트: 컨테이너 기반 클라우드 웹서비스 배포·운영 역량

## 7. 핵심 설명 문장

면접과 포트폴리오에서는 다음 메시지를 기준으로 설명한다.

> 팀 프로젝트에서는 기능 완성과 시연에 집중했지만, 이후 실제 서비스로 설명하려면 기능 구현뿐 아니라 배포 후 상태 확인, Secret 관리, DB 스키마 정합성, CI/CD 검증, 장애 시 점검 절차가 필요하다고 판단했습니다. 그래서 기존 Terraformers 산출물을 기반으로 컨테이너 실행 구조, RDB/Flyway, S3/SQS 연동, Secrets Manager/External Secrets, GitHub Actions 배포 흐름, smoke test와 runbook을 정리해 운영환경 고도화를 수행했습니다.
