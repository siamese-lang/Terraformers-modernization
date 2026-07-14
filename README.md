# Terraformers Modernization

## 1. 프로젝트 개요

**Terraformers Modernization**은 AWS Cloud School 팀 프로젝트 `Terraformers`를 기반으로, 당시 산출물을 현재 기준에서 포트폴리오 제출 가능한 수준의 **컨테이너 기반 클라우드 웹서비스 운영환경 고도화 버전**으로 정리하는 프로젝트입니다.

원본 Terraformers는 사용자가 아키텍처 이미지를 업로드하면 AI 분석 결과를 바탕으로 Terraform 코드 초안을 생성하고, 프로젝트·파일·결과·로그·댓글 등 관련 데이터를 관리하는 웹서비스입니다.

이 저장소의 목적은 AI 생성 품질을 고도화하거나 새로운 개인 서비스를 만드는 것이 아닙니다. 팀 프로젝트 당시 부족했던 운영환경, 배포, 검증, Secret 관리, DB 정합성, CI/CD, 장애 대응 문서화를 후속 작업으로 보강하여 **컨테이너 기반 웹서비스 배포·운영 역량**을 설명할 수 있도록 정리하는 것입니다.

## 2. 프로젝트 설명 제목

포트폴리오에서는 다음 제목으로 설명합니다.

```text
Terraformers: 컨테이너 기반 웹서비스 배포·운영환경 고도화
```

또는 영문 보조 제목으로 다음을 사용할 수 있습니다.

```text
Terraformers Cloud-Native Runtime Modernization
```

## 3. 서비스 기능 범위

서비스 기능은 다음 수준으로 유지합니다.

- 사용자가 AWS 아키텍처 이미지를 업로드합니다.
- Python 분석 서비스가 Bedrock/OpenSearch 기반 분석을 수행합니다.
- 분석 결과를 바탕으로 Terraform 코드 초안을 생성합니다.
- Spring Boot backend가 프로젝트, 파일, 결과, 로그, 댓글 등 업무 데이터를 관리합니다.
- S3에는 업로드 이미지와 생성 파일을 저장하고, RDB에는 metadata와 관계형 업무 데이터를 저장합니다.
- SQS를 통해 AI/Terraform 처리 로그와 결과 흐름을 비동기적으로 다룹니다.

이 프로젝트에서 중요한 것은 “Terraform 코드를 얼마나 잘 생성하는가”가 아니라, 위 서비스 흐름을 컨테이너 기반 클라우드 운영환경에서 어떻게 배포하고 검증하며 장애 시 어디부터 확인할 수 있게 만들었는가입니다.

## 4. 팀 프로젝트와 후속 고도화 구분

### 팀 프로젝트 당시 기여

- 백엔드 일부 기능 구현
- 컨테이너/클라우드 배포 흐름 점검
- S3, 인증, 배포, 결과 조회 등 서비스 흐름 일부 검증
- 팀 프로젝트 전체 산출물 완성에 참여

### 후속 고도화 기여

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

## 5. 아키텍처 요약

```text
User Browser
  |
  | HTTPS
  v
CloudFront
  |-- S3 static frontend
  |-- /api/* backend origin
  v
React Frontend
  |
  | Cognito auth + API request
  v
Spring Boot Backend on container runtime
  |-- RDS MariaDB: users/projects/files/comments/reactions metadata
  |-- S3: uploaded images, generated Terraform files, tfstate objects
  |-- SQS: AI/Terraform progress logs and result messages
  |-- Secrets Manager / External Secrets: runtime config and secret delivery
  |
  | HTTP /analyze
  v
Python Bedrock Analysis Service
  |-- Bedrock: image analysis and Terraform draft generation
  |-- OpenSearch/AOSS: reference search
  |-- SQS publish: progress and final result
```

자세한 내용은 [`docs/architecture.md`](docs/architecture.md)를 기준으로 설명합니다.

## 6. 운영환경 고도화 핵심 포인트

- **RDB 중심 데이터 구조**: 사용자, 프로젝트, 파일, 댓글, 반응 등 관계형 업무 데이터는 RDS MariaDB 기준으로 정리합니다.
- **Schema migration**: Flyway migration과 Hibernate validate로 schema drift를 조기에 확인합니다.
- **Object/metadata 분리**: S3는 실제 파일 content를 저장하고, RDB는 metadata와 관계를 관리합니다.
- **Secret 분리**: DB credential, runtime config, AWS 연동값은 코드와 manifest에서 분리합니다.
- **Container image 관리**: backend와 Python analysis service를 각각 image로 build/publish하고, image tag가 manifest와 runtime에 일치하는지 확인합니다.
- **CI/CD 통제**: PR 검증과 실제 apply/deploy를 분리하고, Terraform apply는 승인 기반 workflow로 실행합니다.
- **배포 후 검증**: rollout status, health check, API smoke, E2E flow, log inspection을 기준으로 운영 상태를 확인합니다.
- **Runbook 문서화**: DB 연결 실패, Secret 누락, SQS 처리 실패, worker 장애, image tag 불일치 등 장애 상황별 점검 절차를 문서화합니다.

## 7. 문서 구조

- [`PROJECT_DIRECTION.md`](PROJECT_DIRECTION.md): 프로젝트 방향 고정 문서
- [`docs/architecture.md`](docs/architecture.md): 시스템 아키텍처와 구성요소 책임
- [`docs/deployment.md`](docs/deployment.md): Docker, Terraform, GitHub Actions, runtime config, 배포 순서
- [`docs/validation.md`](docs/validation.md): 배포 후 smoke/E2E/API/log 검증 절차
- [`docs/runbook.md`](docs/runbook.md): 장애 상황별 운영 점검 절차
- [`docs/interview-guide.md`](docs/interview-guide.md): 포트폴리오·면접 설명 가이드

## 8. 주의: 이 프로젝트가 아닌 것

이 프로젝트는 다음이 아닙니다.

- Terraformers를 완전히 새로 만든 개인 프로젝트
- AI 코드 생성 품질 개선 프로젝트
- Terraform plan 검증·승인 플랫폼
- Backstage, AWS Service Catalog, env0의 하위호환 서비스
- 운영 로그 분석 리포트 서비스
- 프론트엔드 개발 역량 중심 프로젝트
- Terraform 자체를 주제로 삼는 프로젝트

## 9. 다른 운영 프로젝트와의 차별점

별도 개인 프로젝트인 **AWS EC2 기반 다계층 업무시스템 운영환경 구축 및 장애·복구 검증**은 VM 기반 WEB/WAS/DB/NFS 운영환경, 장애·성능·복구 검증, 로그·지표 기반 원인 분석, 백업/복구 runbook을 보여 주는 프로젝트입니다.

반면 이 Terraformers 고도화 프로젝트는 다음 역량을 보여 줍니다.

- 컨테이너 기반 웹서비스 운영
- Spring Boot backend와 Python analysis service 구성
- AWS 관리형 서비스 연동
- RDS, S3, SQS, Secrets Manager 기반 runtime 구성
- GitHub Actions, ECR, Terraform, ArgoCD 기반 배포 흐름
- 배포 후 smoke test와 E2E 검증
- 클라우드 네이티브 서비스 운영 문서화

## 10. 핵심 설명 문장

```text
팀 프로젝트에서는 기능 완성과 시연에 집중했지만, 이후 실제 서비스로 설명하려면 기능 구현뿐 아니라 배포 후 상태 확인, Secret 관리, DB 스키마 정합성, CI/CD 검증, 장애 시 점검 절차가 필요하다고 판단했습니다. 그래서 기존 Terraformers 산출물을 기반으로 컨테이너 실행 구조, RDB/Flyway, S3/SQS 연동, Secrets Manager/External Secrets, GitHub Actions 배포 흐름, smoke test와 runbook을 정리해 운영환경 고도화를 수행했습니다.
```
