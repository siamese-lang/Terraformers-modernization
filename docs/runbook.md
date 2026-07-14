# Runbook

## 1. 목적

이 문서는 Terraformers 운영환경 고도화 프로젝트에서 발생할 수 있는 주요 장애 상황의 점검 순서를 정리한다.

Runbook의 목적은 다음이다.

- 장애 발생 시 감으로 접근하지 않고 계층별로 원인을 좁힌다.
- frontend, backend, analysis service, RDB, S3, SQS, Secret, image tag, CloudFront 문제를 분리한다.
- 면접에서 “장애 상황을 어떻게 확인할 수 있는가”에 답할 수 있는 운영 절차를 남긴다.

## 2. 공통 점검 순서

장애 유형과 관계없이 먼저 다음을 확인한다.

```bash
kubectl get deploy,po,svc,endpoints -n default
kubectl get events -n default --sort-by=.lastTimestamp | tail -80
kubectl rollout status deployment/backend-app -n default
kubectl rollout status deployment/bedrock-service -n default
```

확인 기준은 다음이다.

- Pod가 `Running`인지 확인한다.
- `CrashLoopBackOff`, `CreateContainerConfigError`, `ImagePullBackOff`, `Pending` 여부를 확인한다.
- service endpoint가 존재하는지 확인한다.
- 최근 event에서 scheduling, image pull, secret mount, readiness probe 실패를 확인한다.

## 3. DB 연결 실패

### 증상

- backend pod `CrashLoopBackOff`
- `/actuator/health` 실패
- backend log에 `SQLState`, `Connect timed out`, `Unable to open JDBC Connection` 출력
- startup 중 datasource 초기화 실패

### 우선 확인

```bash
kubectl logs deployment/backend-app -n default -c backend-app --tail=200
kubectl get secret backend-rds-runtime-secrets -n default
kubectl get endpoints -n default
```

### 진단 포인트

| 가능 원인 | 확인 방법 |
|---|---|
| datasource secret key 누락 | Kubernetes Secret key 목록 확인. value는 출력하지 않음 |
| RDS endpoint 오입력 | Terraform output과 runtime secret key 비교 |
| RDS SG inbound 누락 | RDS SG가 EKS node/pod source SG를 허용하는지 확인 |
| JDBC driver 누락 | log에 `Failed to load driver class org.mariadb.jdbc.Driver` 존재 여부 |
| TLS requirement 불일치 | log에 `Connections using insecure transport are prohibited` 존재 여부 |
| schema validation 실패 | log에 `Schema-validation` 또는 `Flyway validation failed` 존재 여부 |

### 조치 방향

1. secret key 존재 여부를 확인한다.
2. datasource URL, username, password가 runtime secret contract에 맞게 주입되는지 확인한다.
3. RDS SG와 EKS source SG 연결을 확인한다.
4. JDBC driver dependency와 image rebuild 여부를 확인한다.
5. TLS required 환경이면 JDBC URL에 SSL parameter를 반영한다.
6. schema 문제라면 Flyway migration 상태를 확인한다.

## 4. Secret 누락

### 증상

- Pod `CreateContainerConfigError`
- backend 또는 bedrock pod가 시작되지 않음
- log에 환경 변수 누락, secretKeyRef 누락 메시지 출력
- ExternalSecret status가 Ready가 아님

### 우선 확인

```bash
kubectl get secret -n default
kubectl get externalsecret -n default
kubectl describe externalsecret backend-runtime-secrets -n default
kubectl describe externalsecret backend-rds-runtime-secrets -n default
kubectl describe externalsecret bedrock-runtime-secrets -n default
```

### 진단 포인트

| 가능 원인 | 확인 방법 |
|---|---|
| External Secrets CRD 미설치 | `kubectl get crd | grep external-secrets` |
| SecretStore 인증 실패 | `kubectl describe secretstore` |
| Secrets Manager key mismatch | ExternalSecret event 확인 |
| target Secret 미생성 | `kubectl get secret -n default` |
| Deployment가 잘못된 secret name 참조 | manifest의 `envFrom` / `secretKeyRef` 확인 |

### 조치 방향

1. External Secrets controller가 설치되어 있는지 확인한다.
2. SecretStore Ready 상태를 확인한다.
3. ExternalSecret event에서 provider access error를 확인한다.
4. target Secret 이름과 Deployment 참조 이름이 일치하는지 확인한다.
5. secret value는 출력하지 않고 key 존재 여부만 확인한다.
6. 수정 후 rollout restart를 수행한다.

## 5. S3 권한 오류

### 증상

- 이미지 업로드 실패
- 생성 Terraform 파일 저장 실패
- backend log 또는 analysis service log에 `AccessDenied`, `NoSuchBucket`, `NoSuchKey` 출력
- RDB metadata는 생성됐지만 S3 object가 없음

### 우선 확인

```bash
kubectl logs deployment/backend-app -n default -c backend-app --tail=200
kubectl logs deployment/bedrock-service -n default --tail=200
```

### 진단 포인트

| 가능 원인 | 확인 방법 |
|---|---|
| bucket name runtime config 불일치 | backend runtime secret key 확인 |
| IAM role S3 권한 부족 | workload role policy 확인 |
| object key 생성 규칙 오류 | RDB metadata와 S3 key 비교 |
| analysis service가 다른 bucket/key 참조 | `/analyze` payload log와 backend upload 결과 비교 |
| region mismatch | AWS region runtime config 확인 |

### 조치 방향

1. upload API 응답에서 projectId/file metadata가 생성됐는지 확인한다.
2. S3 bucket name과 object key가 backend/analysis service에서 동일하게 사용되는지 확인한다.
3. IAM policy에 `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` 등 필요한 권한이 있는지 확인한다.
4. RDB metadata 생성 후 S3 저장 실패가 발생한 경우 보상 삭제 또는 재처리 필요 여부를 판단한다.

## 6. SQS 메시지 처리 실패

### 증상

- frontend에서 진행 로그가 보이지 않음
- Terraform 결과가 표시되지 않음
- backend log에 queue mismatch 또는 polling error 출력
- analysis service log에 SQS publish error 출력

### 우선 확인

```bash
kubectl logs deployment/backend-app -n default -c backend-app --tail=200
kubectl logs deployment/bedrock-service -n default --tail=200
```

### 진단 포인트

| 가능 원인 | 확인 방법 |
|---|---|
| queue URL runtime config 누락 | Secret key 존재 여부 확인 |
| frontend가 stale queueUrl 전달 | upload 응답과 polling 요청 비교 |
| backend queueUrl validation 실패 | backend log의 mismatch 메시지 확인 |
| analysis service publish 실패 | bedrock log의 SQS error 확인 |
| projectId 누락 | SQS message body와 backend filtering 조건 확인 |
| IAM SQS 권한 부족 | workload role policy 확인 |

### 조치 방향

1. queue URL을 secret value로 직접 출력하지 않고 key 존재 여부와 config source를 확인한다.
2. upload 응답에서 전달된 projectId와 queueUrl 흐름을 확인한다.
3. backend polling API가 server-side configured queue URL과 비교하는지 확인한다.
4. analysis service가 final `terraform_result` message를 publish하는지 확인한다.
5. projectId가 message body에 포함되는지 확인한다.

## 7. Python Analysis Service 장애

### 증상

- bedrock pod `CrashLoopBackOff`
- `/health` 실패
- upload 후 AI 분석이 진행되지 않음
- log에 Bedrock/OpenSearch/SQS 오류 출력

### 우선 확인

```bash
kubectl get pod -n default | grep bedrock
kubectl describe pod/<bedrock-pod-name> -n default
kubectl logs pod/<bedrock-pod-name> -n default --previous --tail=120
kubectl logs deployment/bedrock-service -n default --tail=200
```

### 진단 포인트

| 가능 원인 | 확인 방법 |
|---|---|
| image tag 미반영 | deployment image와 Git manifest image 비교 |
| runtime env 누락 | secret key 존재 여부 확인 |
| OpenSearch endpoint parse error | log에 endpoint parsing error 존재 여부 |
| Bedrock model access issue | log에 AccessDenied 또는 model availability error 확인 |
| SQS publish 실패 | log에 send_message error 확인 |
| dependency 문제 | container startup log 확인 |

### 조치 방향

1. image tag consistency를 먼저 확인한다.
2. pod event에서 secret/env 누락 여부를 확인한다.
3. OpenSearch endpoint가 `https://...` 형식인지 bare hostname인지 확인하고 code normalization 여부를 점검한다.
4. Bedrock model ID와 region이 실제 사용 가능한 값인지 확인한다.
5. SQS publish 권한과 queue config를 확인한다.
6. 수정 후 image rebuild/publish, manifest update, ArgoCD sync, rollout status를 순서대로 확인한다.

## 8. 잘못된 image tag 배포

### 증상

- 코드 수정 후에도 같은 오류가 계속 발생
- GitHub Actions는 성공했지만 runtime log가 이전 코드 기준으로 보임
- Deployment image가 DockerHub placeholder 또는 old ECR tag를 가리킴

### 우선 확인

```bash
kubectl get deploy backend-app -n default -o jsonpath='{.spec.template.spec.containers[*].image}'
kubectl get deploy bedrock-service -n default -o jsonpath='{.spec.template.spec.containers[*].image}'
```

### 진단 포인트

| 가능 원인 | 확인 방법 |
|---|---|
| image build만 되고 publish 안 됨 | workflow summary 확인 |
| ECR push는 됐지만 manifest update 안 됨 | Git diff/commit 확인 |
| manifest update는 됐지만 ArgoCD sync 안 됨 | ArgoCD application status 확인 |
| rollout이 old replica를 유지 | `kubectl rollout status` / ReplicaSet 확인 |
| latest tag 사용으로 추적 어려움 | immutable tag 또는 commit SHA 사용 여부 확인 |

### 조치 방향

1. GitHub Actions build/publish 결과를 확인한다.
2. ECR image tag가 생성됐는지 확인한다.
3. manifest image URI가 새 tag로 갱신됐는지 확인한다.
4. ArgoCD sync를 수행한다.
5. Kubernetes deployment image를 다시 확인한다.
6. pod log에서 기대한 코드 변경이 반영됐는지 확인한다.

## 9. Schema migration 실패

### 증상

- backend startup 실패
- log에 `Flyway validation failed`
- log에 `Schema-validation: missing table` 또는 missing column 출력
- RDS 연결은 되지만 application이 시작되지 않음

### 우선 확인

```bash
kubectl logs deployment/backend-app -n default -c backend-app --tail=300
```

DB 내부 확인은 운영자 권한으로 수행한다.

```sql
SELECT installed_rank, version, description, script, success
FROM flyway_schema_history
ORDER BY installed_rank;

SHOW TABLES;
```

### 진단 포인트

| 가능 원인 | 확인 방법 |
|---|---|
| migration 파일 누락 | `db/migration` directory 확인 |
| 실패한 migration history 존재 | `flyway_schema_history.success=0` 확인 |
| 수동 DDL drift | entity와 실제 table/column 비교 |
| 이미 적용된 migration 수정 | checksum mismatch 확인 |
| prod에서 ddl-auto validate 실패 | backend startup log 확인 |

### 조치 방향

1. migration 파일이 코드에 포함되어 있는지 확인한다.
2. 실패 이력이 있으면 dev/prod를 구분해 복구 절차를 다르게 적용한다.
3. dev에서는 failed row cleanup 또는 Flyway repair를 검토할 수 있다.
4. production에서는 snapshot/backup과 변경 승인 후 repair 또는 migration 보정 작업을 수행한다.
5. 임의 DDL로 장기 해결하지 않고 canonical migration 파일로 정리한다.
6. backend image rebuild/redeploy 후 startup log를 재확인한다.

## 10. Health check 실패

### 증상

- `/actuator/health` 500 또는 timeout
- `/health` 500 또는 timeout
- LoadBalancer/CloudFront route는 살아 있지만 API 응답 실패

### 우선 확인

```bash
kubectl get svc,endpoints -n default
kubectl logs deployment/backend-app -n default -c backend-app --tail=200
kubectl logs deployment/bedrock-service -n default --tail=200
```

### 진단 포인트

| 가능 원인 | 확인 방법 |
|---|---|
| pod 자체 미기동 | deployment/pod status 확인 |
| endpoint 없음 | service selector와 pod label 비교 |
| app startup 실패 | application log 확인 |
| DB dependency 실패 | datasource log 확인 |
| CloudFront/API routing 문제 | origin behavior 확인 |
| readiness/liveness probe mismatch | probe path/port 확인 |

### 조치 방향

1. service endpoint가 존재하는지 확인한다.
2. pod log에서 startup 완료 여부를 확인한다.
3. backend health failure는 DB/schema/secret 문제와 연결해 본다.
4. analysis service health failure는 runtime env/Bedrock/OpenSearch config 문제와 연결해 본다.
5. CloudFront 경유 요청이 HTML을 반환하면 `/api/*` behavior를 확인한다.

## 11. CloudFront API routing 문제

### 증상

- API 요청 결과가 JSON이 아니라 React `index.html`임
- browser console에 `Unexpected token '<'` 오류 발생
- OPTIONS preflight 실패
- 인증 header가 backend까지 전달되지 않음

### 우선 확인

```bash
curl -i https://<cloudfront-domain>/actuator/health
curl -i https://<cloudfront-domain>/api/public-projects
curl -i -X OPTIONS https://<cloudfront-domain>/api/upload \
  -H "Origin: https://<cloudfront-domain>" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: authorization,content-type,accept"
```

### 진단 포인트

| 가능 원인 | 확인 방법 |
|---|---|
| `/api/*` behavior 누락 | CloudFront behavior 확인 |
| custom error response가 API error를 SPA fallback으로 치환 | CloudFront error response 확인 |
| Authorization header forwarding 누락 | origin request policy 확인 |
| CORS allowed origin 불일치 | backend CORS config 확인 |
| backend origin target 오류 | origin domain/path 확인 |

### 조치 방향

1. `/api/*`가 backend origin으로 가는지 확인한다.
2. API 401/403/500이 SPA index.html로 치환되지 않도록 확인한다.
3. Authorization, Content-Type, Origin, Access-Control headers forwarding을 확인한다.
4. OPTIONS preflight 응답이 text/html이 아닌지 확인한다.

## 12. 면접 설명 포인트

Runbook을 설명할 때는 다음 문장 구조를 사용한다.

```text
장애가 발생하면 먼저 Pod 상태와 rollout, endpoint를 확인해 runtime 계층 문제인지 분리했습니다. 그다음 backend 로그, analysis service 로그, RDS 연결, Secret sync, S3/SQS 권한, image tag consistency를 순서대로 확인하도록 runbook을 정리했습니다. 특히 workflow 성공과 실제 runtime 반영은 다르기 때문에 manifest image tag와 deployment image를 비교해 배포 불일치를 확인했습니다.
```
