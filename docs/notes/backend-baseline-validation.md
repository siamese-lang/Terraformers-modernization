# Backend Baseline Validation Note

## 1. 현재 상태

`backend/` 디렉터리는 공개 저장소에서 backend 고도화 작업을 진행하기 위한 첫 실행 기준선이다.

추가된 검증 수단:

- Maven test/package workflow
- Docker image build workflow
- local verification script
- runtime config inspector unit test
- runtime readiness controller unit test

## 2. 검증 명령

```bash
bash scripts/checks/backend-local-verification.sh
```

또는 단계별 실행:

```bash
cd backend
mvn -q test
mvn -q -DskipTests package
docker build -t terraformers-backend:local .
```

## 3. 주의

현재 backend baseline은 원본 Terraformers 전체 API 구현을 옮긴 상태가 아니다.

따라서 이 단계의 검증 목표는 다음에 한정한다.

```text
Maven 프로젝트 구조가 유효한가?
Docker image build 기준이 존재하는가?
prod runtime config contract가 secret value 없이 분리되어 있는가?
Flyway schema 기준이 존재하는가?
GitHub Actions로 반복 검증할 수 있는가?
```

원본 서비스 기능 API는 다음 단계에서 공개 가능 여부를 확인한 뒤 선별 이전한다.
