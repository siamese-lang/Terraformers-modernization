# Analysis Service Consolidation Plan

## 1. 검토 결과

기존 Terraformers에는 Python 기반 분석 서비스가 분리되어 있었다.

이 서비스는 이미지 분석과 Terraform 초안 생성을 담당했지만, 실제 책임을 나누어 보면 대부분 다음과 같은 backend orchestration 성격이다.

- 분석 요청 수신
- S3 object 조회
- 이미지 media type 확인
- Bedrock 호출
- OpenSearch/AOSS 검색
- SQS 진행 로그와 결과 메시지 발행
- 처리 결과 반환

따라서 현재 고도화 프로젝트의 기본 방향은 Python 서비스를 필수 runtime으로 유지하는 것이 아니라, Spring Boot backend가 분석 job lifecycle을 소유하도록 정리하는 것이다.

## 2. 목표 구조

```text
Client
  -> Spring Boot Backend
      -> 사용자/프로젝트/파일 context 확인
      -> analysis job 상태를 RDB에 기록
      -> S3 object adapter 호출
      -> Bedrock adapter 호출
      -> OpenSearch adapter 호출
      -> SQS publisher 호출
      -> job status와 결과 metadata 갱신
```

Python service는 기본 배포 경로가 아니라 legacy reference로만 둔다.

## 3. 판단 근거

### 3.1 Python 고유 기능이 강하지 않다

현재 Python 서비스의 핵심은 Python 전용 ML 처리라기보다 AWS SDK 호출과 흐름 제어에 가깝다. Java/Spring Boot에서도 동일한 흐름을 구현할 수 있다.

### 3.2 운영 단위가 줄어든다

Python 서비스를 계속 유지하면 두 번째 image, 두 번째 Deployment, 두 번째 runtime 설정, backend-to-worker HTTP 장애 경로를 별도로 관리해야 한다.

백엔드·클라우드 인프라 중심 포트폴리오에서는 이 복잡도가 장점보다 부담이 크다.

### 3.3 backend 역량 설명이 선명해진다

분석 흐름을 backend가 소유하면 다음을 설명하기 좋다.

- API contract
- RDB job state
- S3/SQS/Bedrock/OpenSearch adapter
- 실패 상태 구분
- 배포 후 smoke test
- runtime readiness
- 장애 runbook

## 4. 이전 단계

1. Python 서비스는 core import 대상에서 제외한다.
2. backend에 analysis job lifecycle을 추가한다.
3. RDB에 analysis job 상태 table을 추가한다.
4. S3, SQS, Bedrock, OpenSearch adapter를 Java backend로 이전한다.
5. Kubernetes/Terraform 문서에서는 Python Deployment를 기본 구성에서 제거한다.
6. 별도 worker가 필요해질 경우 queue-based worker architecture로 재검토한다.

## 5. 면접 설명 문장

```text
원본 팀 프로젝트에는 Python 분석 서비스가 분리되어 있었지만, 역할을 검토해 보니 대부분 S3 조회, Bedrock 호출, OpenSearch 검색, SQS 발행 같은 backend orchestration이었습니다. 고도화 목표가 백엔드와 클라우드 인프라였기 때문에 Python을 필수 runtime으로 유지하기보다 Spring Boot backend가 분석 job lifecycle과 AWS adapter를 소유하도록 정리하는 방향이 더 적절하다고 판단했습니다.
```
