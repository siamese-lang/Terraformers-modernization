# Terraformers 최종 증빙 및 면접 설명 가이드

## 1. 문서 목적

이 문서는 AWS 리소스를 철거한 뒤에도 Terraformers-modernization 프로젝트를 구체적으로 설명할 수 있도록 다음을 고정한다.

- 프로젝트의 실제 목표와 개인 기여 범위
- 구현한 내용과 라이브 검증한 내용의 구분
- 주요 난관과 근본 원인
- 잘못된 초기 가정과 판단 수정 과정
- 수정 범위를 좁힌 근거
- 면접에서 받을 수 있는 후속 질문
- 과장해서는 안 되는 영역

이 문서는 성공한 기능만 나열하는 홍보 문서가 아니다. **문제가 발생한 경계와 그것을 어떻게 좁혀 해결했는지**를 설명하기 위한 운영 기록이다.

## 2. 프로젝트 정체성

### 프로젝트 한 문장 설명

> 2024년 AWS Cloud School 5인 팀 프로젝트인 Terraformers를 기반으로, 기존 기능을 새로 만드는 대신 백엔드·RDB·AWS 인프라·Secret 전달·CI/CD·GitOps·관측성·장애 대응 구조를 현재 기준에 맞게 고도화한 프로젝트입니다.

### 프로젝트에서 해결하려 한 문제

원본 서비스는 아키텍처 이미지를 입력받아 Terraform 코드 초안을 생성하고 프로젝트·파일·결과·댓글을 관리하는 웹서비스였다. 그러나 팀 프로젝트 종료 시점에는 다음이 충분히 정리되지 않았다.

- 백엔드 도메인과 RDB 스키마의 책임 경계
- S3 객체와 RDB 메타데이터의 일관성
- Cognito 사용자와 백엔드 사용자 매핑
- EKS 런타임 Secret 전달
- 실제 AWS 배포와 복구 가능한 Terraform 상태
- immutable image와 배포 상태의 일치
- GitOps 기반 변경·롤백 경로
- Bedrock/AOSS 비동기 분석 실패 진단
- CloudWatch 로그·메트릭·트레이스의 상관관계
- 전체 환경 삭제 및 재배포 절차

따라서 목표는 AI 기능을 계속 확장하는 것이 아니라, **팀 프로젝트를 실제로 배포·운영·진단·복구·철거할 수 있는 구조로 재정렬하는 것**이었다.

## 3. 개인 기여를 설명하는 기준

면접에서는 2024년 팀 프로젝트와 이후 개인 고도화를 구분한다.

### 팀 프로젝트 당시

- AWS Bedrock과 OpenSearch 기반 RAG를 활용한 아키텍처 이미지 분석 및 Terraform 코드 생성 서비스
- EKS 기반 백엔드, S3·CloudFront 웹 환경, Terraform 인프라, GitHub Actions·Argo CD 활용
- 팀 단위 설계와 구현

### 이후 개인 고도화

- 원본 저장소와 1차 RDB refactor 저장소를 비교하여 재사용·폐기·개선 범위 결정
- Spring Boot 중심 분석 흐름과 도메인/RDB 책임 재정렬
- AWS OIDC 기반 Terraform plan/apply 경계와 원격 state 복구
- EKS, RDS, S3, SQS, Cognito, Secrets Manager, CloudFront, Bedrock, AOSS 연동 검증
- immutable ECR digest와 Argo CD desired state 연결
- RAG corpus v2와 버전 필터링 비교
- CloudWatch/Application Signals/X-Ray 기반 관측성 소스 구성
- 실패 로그를 기반으로 JSON 파싱, SigV4, IAM, Terraform state, controller owner 문제 해결
- 종료 시점 resource inventory, teardown, redeploy runbook 작성

“제가 2024년에 전부 설계·구현했다”라고 설명하지 않는다. **팀 결과물을 기준으로 이후 어떤 운영·백엔드 문제를 개인적으로 재설계하고 검증했는지**를 설명한다.

## 4. 최종 증빙 상태표

AWS 철거 전에 실제 값을 채운다. 값이 없으면 성공으로 추정하지 않는다.

| 증빙 항목 | 최종 값 | 상태 | 근거 |
|---|---|---|---|
| integration commit | PENDING_FINAL_EVIDENCE | 미확정 | Git integration branch |
| Backend source commit | PENDING_FINAL_EVIDENCE | 미확정 | image workflow |
| ECR immutable digest | `sha256:2f4a177a06d1e64819b06240a441e619105980e43dea04b3f4709a86e2d95c73` 또는 최종 교체 값 | 확인 필요 | image publish / PR #83 |
| Argo CD revision | PENDING_FINAL_EVIDENCE | 미확정 | Application status |
| Argo CD sync/health | PENDING_FINAL_EVIDENCE | 미확정 | `Synced/Healthy` 확인 |
| Deployment image | PENDING_FINAL_EVIDENCE | 미확정 | Kubernetes Deployment |
| Pod runtime image ID | PENDING_FINAL_EVIDENCE | 미확정 | Kubernetes Pod status |
| browser login/upload/analysis/result | PENDING_FINAL_EVIDENCE | 미확정 | CloudFront browser smoke |
| RAG corpus version | `terraformers-reference-v2` | 완료 | PR #73 |
| RAG provider version | `5.100.0` | 완료 | PR #73 |
| corpus document count | `128` | 완료 | ingestion evidence |
| v1/v2 median pipeline | `45.120 s -> 48.222 s` | 완료 | PR #73 comparison |
| Application Signals | PENDING_FINAL_EVIDENCE | source merge만으로 성공 주장 금지 | CloudWatch service/metric evidence |
| X-Ray trace | PENDING_FINAL_EVIDENCE | source merge만으로 성공 주장 금지 | trace ID/service map |
| custom analysis metrics | PENDING_FINAL_EVIDENCE | 실제 emitted metric 확인 필요 | CloudWatch namespace |
| AWS resource inventory | PENDING_CLOSURE_GATE_1 | 미완료 | state inventory + live read-only scan |
| runtime teardown result | PENDING_APPROVAL | 미실행 | teardown runbook |
| bootstrap teardown result | PENDING_APPROVAL | 미실행 | residual scan |

## 5. 면접 답변 구조

### 90초 요약

> Terraformers는 2024년 5인 팀 프로젝트로, 아키텍처 이미지를 분석해 Terraform 코드 초안을 생성하는 서비스였습니다. 이후 저는 기능을 새로 만드는 대신 운영 가능한 구조로 고도화했습니다. 원본과 1차 RDB 리팩터링 저장소를 비교해 도메인과 스키마를 재사용하고, Spring Boot가 분석 생명주기를 소유하도록 정리했습니다. AWS에서는 EKS, RDS, S3, SQS, Cognito, Secrets Manager, CloudFront, Bedrock, OpenSearch Serverless를 Terraform 원격 state와 GitHub OIDC 승인 흐름으로 배포했습니다. Backend 이미지는 immutable digest로 배포하고 Argo CD가 Git desired state를 반영하도록 바꿨습니다. 실제 운영 과정에서는 부분 적용된 Terraform state, AOSS SigV4 403, Bedrock JSON 응답 잘림, CloudWatch Application Signals 주입 실패처럼 여러 경계 문제가 발생했습니다. 각 문제를 권한이나 설정 전체를 넓히지 않고 실제 실패 지점의 증거를 기준으로 수정했습니다. 마지막에는 AWS 전체 리소스를 inventory하고 순서대로 철거한 뒤 다시 배포할 수 있는 runbook까지 정리했습니다.

### 5분 설명 순서

1. 원본 팀 프로젝트와 개인 고도화의 구분
2. 재사용 우선의 백엔드·RDB 재정렬
3. AWS 배포 구조와 Terraform state 분리
4. immutable image와 GitOps 배포 흐름
5. RAG corpus v2의 범위와 품질 비교
6. 대표 장애 두 건의 진단 과정
7. 관측성과 증빙 구조
8. 전체 철거·재배포 가능성
9. 구현하지 않은 영역과 한계

### 기술 심층 설명 원칙

- 서비스 이름보다 **책임 경계**를 먼저 설명한다.
- 명령어보다 **어떤 증거가 가설을 배제했는지**를 설명한다.
- 실패 횟수를 숨기지 않되, 반복 작업 자체를 성과로 포장하지 않는다.
- 권한을 넓힌 것이 아니라 최종적으로 어떻게 최소 범위로 수렴했는지 설명한다.
- “정상”이라는 표현은 브라우저, 런타임, 데이터, desired state, telemetry 중 무엇을 확인했는지 붙여 말한다.

## 6. 난관 기록 형식

모든 대표 사건은 다음 순서로 설명한다.

1. **상황과 목표**
2. **관찰된 현상**
3. **초기 가정과 왜 부족했는지**
4. **확인한 증거**
5. **근본 원인**
6. **수정 범위를 제한한 기준**
7. **수정 내용**
8. **검증 결과**
9. **재발 방지 또는 구조적 교훈**
10. **남은 한계**
11. **면접 후속 질문**

## 7. 대표 난관 1 - 기존 코드를 버리지 않고 도메인과 RDB 책임 재정렬

### 상황과 목표

원본 Terraformers와 1차 `rdb-refactor` 저장소에는 사용자, 프로젝트, 파일, 분석 결과, 로그, 댓글 기능과 RDB 스키마가 이미 존재했다. 고도화 과정에서 모든 것을 새로 만들면 팀 프로젝트와의 연속성이 사라지고 면접에서 변경 이유를 설명하기 어려웠다.

### 관찰된 문제

- 원본 API와 리팩터링 API가 완전히 같지 않았다.
- 임시 호환 코드가 핵심 도메인처럼 보일 위험이 있었다.
- S3 객체 저장과 RDB 메타데이터 저장 책임이 섞여 있었다.
- Cognito 식별자와 내부 사용자 ID의 관계가 불명확했다.
- 분석 상태와 결과 저장 흐름이 동기·비동기 코드에 분산되어 있었다.

### 초기 가정의 문제

“현대화하려면 새 도메인 모델로 전면 재작성해야 한다”는 접근은 빠르게 보이지만, 기존 데이터와 API 호환성, 팀 프로젝트 설명 가능성, 실제 재사용 가능한 마이그레이션과 서비스 로직을 잃는다.

### 확인한 증거

- 원본 엔티티·테이블·API 목록
- `rdb-refactor`의 migration, entity, service, compatibility logic
- 프론트엔드가 실제 호출하는 API
- DB와 S3가 각각 보관하는 정보
- 비동기 분석 상태 전이와 polling 경로

### 근본 원인

기능 부족보다 **도메인 소유권과 저장 책임이 명시되지 않은 것**이 문제였다.

### 수정 범위

- 재사용 가능한 entity, migration, service와 API compatibility를 구분
- Spring Boot가 분석 생명주기를 소유
- RDB는 사용자·프로젝트·파일 메타데이터·분석 상태·결과 참조를 소유
- S3는 원본 이미지와 결과 파일 객체를 소유
- Cognito subject는 인증 식별자이며 내부 사용자 데이터와 매핑
- 임시 호환 API가 핵심 도메인을 다시 정의하지 않도록 제한

### 검증과 교훈

화면이 동작하는지만 보지 않고 요청, DB 반영, S3 객체, 분석 상태, 최종 결과 조회가 같은 흐름으로 이어지는지 확인했다. 핵심 교훈은 **리팩터링은 새 코드를 많이 만드는 작업이 아니라 기존 책임을 명시하고 충돌하는 소유권을 제거하는 작업**이라는 점이다.

### 남은 한계

원본 팀 프로젝트와 고도화 저장소의 전체 변경 이력을 한 문서에서 완벽히 추적하지는 않는다. 면접에서는 대표 변경과 이유를 선택해 설명한다.

### 예상 후속 질문

- 왜 microservice로 분리하지 않았는가?
- RDB와 S3 저장이 일부 성공하고 일부 실패하면 어떻게 처리하는가?
- Cognito 사용자와 내부 사용자 레코드가 불일치하면 어떻게 복구하는가?
- 기존 API 호환성을 언제 제거할 수 있는가?

## 8. 대표 난관 2 - 부분 적용된 Terraform state와 IAM 권한 복구

### 상황과 목표

RAG와 Operations Visibility를 실제 AWS에 적용하는 과정에서 plan 검증은 통과했지만 apply 중간에 IAM 권한 부족이나 AWS 서비스 동작 차이로 실패했다. 일부 리소스는 이미 생성되어 remote state에 기록되고, 나머지만 미생성된 상태가 반복되었다.

### 관찰된 현상

- 저장된 plan apply가 중간 실패
- 다음 plan의 생성 개수가 이전과 달라짐
- AOSS 관리형 VPC endpoint 생성 중 EC2/Route 53 권한 부족
- S3 암호화 API action 이름 불일치
- security group inline rule과 standalone rule의 소유권 충돌
- Operations Visibility 권한을 inline policy로 추가했을 때 IAM role policy 크기 한도 초과
- EKS add-on 생성 시 불필요한 request tag가 추가 권한 평가를 유발

관련 변경은 PR #58~65, #78~82에 집중되어 있다.

### 초기 가정의 문제

“처음 승인한 정확한 resource count를 계속 유지해야 안전하다”는 접근은 부분 적용 이후의 실제 state를 반영하지 못했다. 반대로 매 실패마다 새로운 recovery contract를 추가하면 검증 체계가 프로젝트 목표보다 커졌다.

### 확인한 증거

- remote state serial과 resource address
- saved plan의 실제 create/read/update/delete action
- AWS AccessDenied action/resource/condition
- Terraform plan changed path
- IAM role에 이미 붙은 inline policy 크기
- EKS add-on 요청에서 실제 평가된 tag action

### 근본 원인

하나의 문제가 아니라 다음 세 경계가 겹쳤다.

1. AWS API가 내부적으로 수행하는 부가 동작과 IAM 조건의 불일치
2. 부분 apply 이후 plan shape 변화
3. 같은 속성을 inline block과 standalone resource가 동시에 관리한 Terraform ownership 충돌

### 수정 범위

- 광범위한 관리형 정책 대신 실제 실패한 action/resource/condition만 추가
- 부분 state에서는 승인된 전체 집합의 **state-aware subset recovery**만 허용
- security group ingress 소유권을 standalone rule로 통일
- inline policy 크기 한도 문제는 동일 policy document를 customer-managed policy attachment로 전환
- 불필요한 EKS add-on request tag 제거
- 복구 후 한 번의 no-diff plan으로 ownership 정상화 확인

### 검증과 교훈

핵심은 “apply가 실패했으니 처음부터 삭제하고 다시 만들자”가 아니라 **현재 state에서 무엇이 이미 성공했는지 확인하고 남은 경계만 복구**한 것이다. 또한 승인 계약은 resource count 자체보다 허용 주소·action·changed path·위험 범위를 중심으로 설계해야 한다는 점을 배웠다.

### 남은 한계

승인형 apply contract가 일반 조직의 표준 배포 플랫폼은 아니다. 이 프로젝트에서는 개인 AWS 계정에서 실수 범위를 제한하기 위한 경계로 사용했다.

### 예상 후속 질문

- 왜 state import나 수동 state edit를 사용하지 않았는가?
- IAM 최소 권한을 어떻게 검증했는가?
- 부분 apply 중에 애플리케이션이 노출될 위험은 없었는가?
- destroy 시에도 같은 승인 contract가 필요한가?

## 9. 대표 난관 3 - Bedrock 응답과 AOSS 요청이 각각 다른 경계에서 실패

### 상황과 목표

Backend는 이미지에서 구조화된 facts를 추출하고, embedding을 만든 뒤 AOSS에서 관련 Terraform reference를 검색하고, 최종 Terraform 초안을 생성해야 했다.

### 관찰된 현상

- Bedrock facts 응답이 Markdown fence로 감싸져 JSON parsing 실패
- opening fence 뒤에 줄바꿈이 없는 compact fence 변형에서도 실패
- JSON 앞뒤 설명문이 존재
- 출력 token 300 제한으로 JSON 닫는 중괄호 전에 응답 종료
- 동일 IRSA와 AOSS policy인데 SigV4 요청은 HTTP 403
- custom document ID와 explicit refresh가 AOSS Serverless 동작과 맞지 않음

관련 변경은 PR #66~72에 집중되어 있다.

### 초기 가정의 문제

처음에는 IAM이나 AOSS data access policy가 원인이라고 보기 쉬웠다. 그러나 동일 Pod identity에서 payload hash header 포함 여부만 바꿨을 때 403과 200이 갈렸다. Bedrock 응답도 “모델이 JSON을 반환한다”는 prompt 계약만으로는 실제 형식 변형과 truncation을 막지 못했다.

### 확인한 증거

- Jackson parsing exception의 첫 문자와 응답 prefix
- 실제 live 응답의 fence 형태
- `stop_reason=max_tokens`
- 같은 요청 body에 대한 SHA-256 hash
- SigV4 canonical request와 transmitted headers
- 동일 identity로 수행한 403/200 비교
- AOSS document count와 대표 k-NN visibility 시간

### 근본 원인

- Bedrock: 응답 형식과 길이를 prompt만으로 통제한다고 가정한 parser 설계
- AOSS: exact payload hash가 canonical request와 header에 포함되지 않은 SigV4 서명
- ingestion: 일반 OpenSearch 동작을 Serverless vector collection에도 그대로 적용한 API 가정

### 수정 범위

- Markdown layout 자체를 해석하지 않고 첫 JSON object의 balanced brace 범위를 추출
- 문자열 내부 brace와 escape를 보존
- facts output budget을 800으로 높이고 배열·항목 길이를 제한
- `stop_reason=max_tokens`를 명시적으로 보고
- exact UTF-8 request bytes의 SHA-256을 `X-Amz-Content-Sha256`에 포함하고 서명
- custom document ID 대신 `documentId` 필드 기반 중복 확인
- unsupported refresh 호출 제거 후 bounded convergence polling

### 검증과 교훈

하나의 “RAG 실패”로 묶지 않고 facts parsing, embedding, network, signing, retrieval, generation 단계로 분리한 것이 중요했다. 교훈은 **관리형 서비스 연동 문제에서는 IAM만 반복해서 수정하지 말고 요청 canonicalization과 실제 서비스 API 차이를 함께 확인해야 한다**는 점이다.

### 남은 한계

외부 모델 출력은 완전히 결정적이지 않다. parser와 budget으로 실패 가능성을 줄였지만, 생성 Terraform은 여전히 검토 가능한 초안이다.

### 예상 후속 질문

- balanced brace parser가 잘못된 JSON을 정상으로 오인하지 않는가?
- SDK 대신 직접 SigV4 HTTP 요청을 사용한 이유는 무엇인가?
- 재시도와 idempotency는 어떻게 보장했는가?
- Bedrock timeout과 AOSS timeout을 어떻게 구분했는가?

## 10. 대표 난관 4 - RAG 품질 개선을 프로젝트 목표 안에서 제한

### 상황과 목표

초기 corpus v1은 private Bedrock -> AOSS 경로가 동작함을 증명했지만, 요약 중심 문서와 공용 index 검색 때문에 관련 없는 EKS/AOSS reference가 선택되고 생성 결과가 이미지 구조와 맞지 않는 경우가 있었다.

### 판단 위험

RAG 품질을 높이기 위해 reranker, 평가 플랫폼, 검색 서비스, 새로운 index, 추가 생성 단계까지 확장할 수 있었지만, 그렇게 하면 프로젝트가 백엔드·클라우드 운영 고도화가 아니라 RAG 연구 프로젝트로 바뀐다.

### 수정 범위

PR #73에서 범위를 한 번의 v2 개선으로 제한했다.

- AWS Provider 5.100.0 기준 128개 curated chunk
- 30개 resource overview
- 60개 complete HCL example
- 30개 Provider schema summary
- 8개 project decision
- corpus/provider version filter
- architecture facts에서 얻은 resource type filter
- topK 3에서 8로 확대
- 동일 immutable Backend image와 동일 3개 이미지로 v1/v2 비교

### 결과

- median pipeline latency: `45.120 s -> 48.222 s` (`+6.9%`)
- median vector search latency: `0.222 s -> 0.269 s`
- 공식 Provider schema/example reference가 실제 선택됨
- 3개 사례 중 2개에서 방향성 개선
- MongoDB 설치·replica set·인증과 같은 cross-service correctness는 여전히 생성 단계 한계

### 교훈

기능 개선의 종료 조건을 미리 정하지 않으면 평가 체계 자체가 프로젝트가 된다. 이 작업에서는 **검색 relevance와 실제 생성 결과의 방향성 개선을 확인한 뒤 RAG를 종료**했다.

### 예상 후속 질문

- 3개 사례로 품질 향상을 주장할 수 있는가?
- latency 증가를 허용한 이유는 무엇인가?
- 공식 문서가 있는데도 잘못된 Terraform이 생성되는 이유는 무엇인가?
- 다음 개선 한 가지를 고른다면 무엇인가?

## 11. 대표 난관 5 - immutable image와 GitOps desired state 일치

### 상황과 목표

기존 image publish와 Kubernetes 배포 경로는 있었지만, 어떤 Git commit과 ECR image가 현재 runtime인지 설명하기 어려웠다. 직접 `kubectl set image`를 사용하면 Git과 cluster 상태가 분리된다.

### 수정 범위

PR #75~76과 #83에서 다음 흐름을 고정했다.

```text
Backend source commit
  -> GitHub OIDC image build/push
  -> immutable git-<full-sha> tag
  -> ECR digest resolution
  -> digest-only GitOps manifest PR
  -> merge
  -> Argo CD reconcile
  -> Deployment image / Pod image ID parity
```

Argo CD는 internal ClusterIP로 설치하고, Backend overlay의 ConfigMap·Service·Deployment만 관리하도록 범위를 제한했다. Secret, ExternalSecret, Ingress, Namespace는 별도 owner를 유지했다.

### 어려웠던 점

- source commit과 manifest merge commit은 의도적으로 다르다.
- 태그가 아니라 digest를 기준으로 runtime parity를 확인해야 한다.
- Argo CD self-heal이 수동 drift를 복구하는지와 실제 release rollback은 다른 시나리오다.
- GitOps overlay가 기존 base와 ServiceAccount ownership을 중복 관리하지 않아야 했다.

### 교훈

배포 성공을 “workflow가 성공했다”로 설명하지 않고 **source revision, image digest, Git desired state, Deployment image, Pod runtime image ID, browser outcome**으로 연결해야 한다.

### 남은 한계

고가용 Argo CD나 다중 cluster 운영은 구현하지 않았다. 이 프로젝트에서 Argo CD의 목적은 release desired state와 rollback 경로를 명확히 하는 것이다.

### 예상 후속 질문

- mutable tag가 왜 문제인가?
- image workflow가 manifest PR을 만드는 것이 안전한가?
- Argo CD가 장애 나면 어떻게 배포하는가?
- rollback과 roll-forward 중 무엇을 선호하는가?

## 12. 대표 난관 6 - Application Signals가 소스상 활성인데 Java agent가 주입되지 않음

### 상황과 목표

CloudWatch Observability add-on, Micrometer metric, dashboard, alarm, Java auto-instrumentation annotation을 구성해 Backend 요청을 metric, log, trace, source revision으로 연결하려 했다.

### 관찰된 현상

- add-on은 Active인데 Backend Pod에 OpenTelemetry init container와 `OTEL_*`, `JAVA_TOOL_OPTIONS`가 없음
- custom CloudWatch agent config 적용 후 Application Signals metric/trace receiver가 사라짐
- Micrometer base meter와 실제 CloudWatch emitted metric suffix가 달라 dashboard/alarm이 비어 있음
- workload annotation은 존재하지만 `monitorAllServices=false` 상태에서 선택된 workload가 없음
- workload selector를 추가한 뒤에도 Pod-level `runAsNonRoot=true`이고 Pod-level `runAsUser`가 없어 operator가 Java injection을 건너뜀

관련 변경은 PR #77~86에 집중되어 있다.

### 초기 가정의 문제

- add-on Active를 telemetry 성공으로 간주할 수 없다.
- annotation 존재를 mutation 성공으로 간주할 수 없다.
- Micrometer 코드의 meter 이름을 CloudWatch metric 이름으로 그대로 사용할 수 없다.
- container-level UID가 injected init container에도 자동 적용된다고 볼 수 없다.

### 확인한 증거

- add-on `configurationValues`
- Pod annotation, initContainers, container env
- CloudWatch agent operator 동작과 manager selector
- 실제 emitted metric names의 `.count`, `.avg`, `.sum`, `.max` suffix
- Pod securityContext와 container securityContext 차이
- PR #86의 Pod-level `runAsUser: 10001`

### 근본 원인

1. custom agent config가 기본 Application Signals receiver를 포함하지 않음
2. `monitorAllServices=false`인데 Backend custom selector가 없음
3. operator가 injected init container의 non-root UID를 결정할 수 없음
4. dashboard/alarm이 실제 emitted metric 이름과 불일치

### 수정 범위

- Application Signals metric/trace receiver 복원
- Backend Deployment 하나만 Java custom selector로 지정
- `monitorAllServices=false` 유지
- Pod-level `runAsUser: 10001` 추가
- dashboard/alarm을 실제 CloudWatch emitted metric 이름으로 정렬
- node group, network, public route, image digest, 다른 workload는 변경하지 않음

### 검증 기준

최종 증빙에서는 다음을 각각 확인해야 한다.

- add-on Active
- Backend Pod Ready, restart 0
- annotation 존재
- init container와 OTEL/JAVA_TOOL_OPTIONS 존재
- Application Signals service/latency/fault/error series
- X-Ray trace 또는 service map
- custom analysis/Bedrock/AOSS metric
- source revision과 safe log correlation

소스 merge와 add-on Active만 확인되었다면 성공으로 기록하지 않는다.

### 교훈

관측성은 agent 설치, workload selection, runtime mutation, metric naming, backend export, dashboard query가 모두 맞아야 동작한다. **각 계층을 분리해 확인하지 않으면 정상처럼 보이는 빈 dashboard만 남는다.**

### 예상 후속 질문

- 왜 Prometheus/Grafana 대신 CloudWatch를 선택했는가?
- `monitorAllServices=true`로 바꾸지 않은 이유는 무엇인가?
- metric label cardinality를 어떻게 제한했는가?
- trace와 application log를 어떻게 연결하는가?
- Pod securityContext가 injection에 왜 영향을 주는가?

## 13. 대표 난관 7 - 로컬 환경 제약과 원격 실행 경계

### 상황

로컬 Windows 환경은 저장 공간이 부족했고 Docker Desktop Linux engine과 Maven/Terraform 사용이 안정적이지 않았다. 긴 Terraform provider cache와 여러 작업 디렉터리를 로컬에 유지하는 방식은 반복 실패와 작업 지연을 만들었다.

### 잘못된 접근

- 실패할 때마다 로컬 격리 작업 디렉터리와 새 스크립트를 생성
- 같은 plan을 여러 번 검증
- Git Bash와 PowerShell 구문을 혼합
- 로컬 도구 부재를 해결하기 위해 검증 체계를 계속 추가

### 최종 방향

- GitHub-hosted runner를 canonical Terraform plan/apply/destroy 환경으로 사용
- OIDC와 원격 S3 state로 로컬 credential/state 의존 제거
- 로컬은 `git`, `gh`, `aws`, `kubectl` operator 역할만 담당
- 완전 철거 후 첫 bootstrap만 독립 AWS 관리자 세션 또는 CloudShell에서 수행
- 이후 stage는 GitHub Actions로 복귀
- raw plan/state/tfvars는 artifact로 남기지 않음

### 교훈

도구 부족을 우회하는 스크립트가 프로젝트 목표보다 커지면 운영 자동화가 아니라 작업 방식의 부채가 된다. **반복적으로 필요한 실행 환경을 원격 runner로 표준화하고 로컬은 제어면으로 축소**했다.

### 예상 후속 질문

- GitHub Actions가 장애 나면 어떻게 배포하는가?
- CloudShell bootstrap의 권한은 어떻게 제한하는가?
- remote state가 손상되면 어떻게 복구하는가?
- 비용과 보안을 위해 self-hosted runner를 고려했는가?

## 14. 면접에서 사용할 대표 사건 선택

모든 사건을 말하지 않는다. 질문에 따라 다음 조합을 사용한다.

### 클라우드 인프라·Terraform 직무

1. 부분 apply와 remote state recovery
2. IAM 최소 권한과 AOSS VPC endpoint
3. 전체 teardown/redeploy lifecycle

### Kubernetes·DevOps 직무

1. immutable digest와 Argo CD desired state
2. controller-owned ALB 삭제 순서
3. Application Signals injection과 Pod security context

### 백엔드·플랫폼 직무

1. 기존 도메인/RDB 재사용과 책임 분리
2. 비동기 분석 단계별 실패 경계
3. safe correlation과 bounded metrics

### 장애 대응 질문

1. AOSS SigV4 403
2. Bedrock JSON truncation/fence
3. add-on Active지만 agent injection 실패

## 15. 과장 금지 항목

다음은 구현 또는 검증했다고 주장하지 않는다.

- 생성된 Terraform의 자동 apply 또는 운영 배포 가능성
- 애플리케이션 multi-AZ 고가용성
- HPA/JMeter 기반 autoscaling 완료
- RDS point-in-time restore 실증
- multi-region disaster recovery
- 무중단 배포의 정량적 보장
- 모든 AWS 리소스의 Terraform-only 관리
- Application Signals/X-Ray 성공 여부가 최종 live evidence에 없을 때의 성공 주장
- 2024년 팀 구현 전체를 개인 기여로 설명
- 대규모 RAG 품질 평가나 통계적 유의성

## 16. 최종 evidence bundle 구성

AWS 철거 전에 다음만 저장한다.

```text
portfolio-evidence/
  final-state-summary.md
  architecture-current.png
  gitops-runtime-parity.txt
  browser-smoke-summary.txt
  rag-v2-comparison-summary.md
  operations-visibility-summary.md
  incident-summary.md
  aws-resource-inventory-summary.md
  teardown-residual-summary.txt
```

포함 금지:

- tfstate, tfvars, saved plan
- kubeconfig
- AWS credentials, tokens, Secret values
- Cognito subject/token
- source image 원본
- Bedrock prompt/response 원문
- retrieved reference content
- generated Terraform 전체
- account-specific private endpoint와 민감 ARN 목록
- raw CloudWatch log dump

## 17. 최종 점검 질문

AWS를 삭제하기 전에 다음 질문에 문서만 보고 답할 수 있어야 한다.

1. 이 프로젝트는 원본 팀 프로젝트와 무엇이 다른가?
2. 개인 기여 범위는 어디까지인가?
3. 왜 모든 것을 새로 만들지 않았는가?
4. Backend, RDB, S3, Cognito의 책임은 어떻게 나뉘는가?
5. source commit과 runtime image를 어떻게 연결했는가?
6. 부분 Terraform apply를 왜 삭제·재생성하지 않았는가?
7. AOSS 403의 원인은 왜 IAM policy가 아니었는가?
8. RAG v2의 개선과 한계는 무엇인가?
9. Application Signals가 동작하지 않은 원인을 어떻게 분리했는가?
10. Terraform으로 관리되지 않는 AWS 리소스는 무엇인가?
11. EKS를 삭제하기 전에 어떤 리소스를 먼저 제거해야 하는가?
12. 완전 철거 후 GitHub Actions를 어떻게 다시 bootstrap하는가?
13. 구현하지 않은 기능을 왜 제외했는가?
14. 같은 프로젝트를 다시 진행한다면 무엇을 먼저 설계할 것인가?

## 18. 새 대화 인계 문구

> Terraformers-modernization 포트폴리오 종료 작업을 이어간다. 먼저 `docs/current-operations-delivery-plan.md`와 `docs/portfolio/final-evidence-and-interview-guide.md`를 읽고, 첫 번째 미완료 Closure Gate부터 진행한다. 프로젝트는 2024년 5인 팀 프로젝트의 백엔드·클라우드 운영환경 고도화이며 새 개인 프로젝트가 아니다. 원본과 `rdb-refactor`의 재사용 결정을 유지한다. RAG, autoscaling, 모니터링 도구, 프론트엔드 기능을 새로 확장하지 않는다. 실제 evidence가 없는 성공을 주장하지 않는다. 면접용 incident는 현상-초기 가정-증거-근본 원인-제한된 수정-검증-교훈 구조로 기록한다. inventory와 retention 결정 전에는 destroy workflow를 만들거나 AWS를 삭제하지 않는다. AWS/Kubernetes/Terraform/Argo CD mutation과 PR merge는 명시적 승인 후에만 수행한다.