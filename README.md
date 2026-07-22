# Terraformers Modernization

## 프로젝트 상태

Terraformers Modernization은 **2024년 AWS Cloud School 5인 팀 프로젝트 `Terraformers`를 기반으로 한 후속 개인 고도화**입니다. 원본 저장소의 서비스 목적과 `siamese-lang/rdb-refactor`의 도메인·RDB 재사용 결정을 유지하고, 이를 Spring Boot, AWS 운영 경계, 배포 및 lifecycle 문서로 정리했습니다. 2024년 팀 구현 전체를 개인 구현으로 주장하지 않습니다.

| 구분 | 정확한 상태 |
|---|---|
| `last_verified_deployed_architecture` | EKS Backend, RDS, S3, Cognito, Bedrock, AOSS, CloudFront private origin, External Secrets/IRSA, immutable ECR digest와 Argo CD GitOps를 사용한 마지막 검증 배포 구조 |
| `current_aws_runtime_status` | 현재 실행 중인 runtime 없음 |
| `runtime_teardown_status` | verified — read-only runtime closure run `29904386655` passed; six runtime Terraform states and exact active runtime AWS counts are all 0 |
| `bootstrap_closure_status` | bootstrap inventory passed; deletion not executed; zero-resource proof not complete |

따라서 아래의 기능과 아키텍처는 **현재 온라인 서비스의 주장**이 아니라 마지막으로 검증된 배포와 저장소가 재구축할 수 있도록 문서화한 설계입니다. 실행되지 않는 CloudFront URL을 제공하지 않습니다.

## 마지막 검증 배포 아키텍처와 책임

```text
CloudFront -> private S3 (OAC) / VPC origin -> internal ALB -> Spring Boot Backend on EKS
Backend -> Cognito, RDS MariaDB, S3, Bedrock, private AOSS, SQS adapter
Secrets Manager -> External Secrets -> Kubernetes Secret
GitHub OIDC -> approved Terraform plan/apply -> remote Terraform state
Backend commit -> immutable ECR digest -> GitOps change -> Argo CD reconciliation
CloudWatch / Application Signals / X-Ray <- bounded telemetry
```

- **Backend·RDB·S3·Cognito:** 인증 사용자와 owner-based RDB domain, 프로젝트 metadata, 업로드·결과 object 책임을 분리했습니다.
- **Bedrock·AOSS:** Spring Boot가 analysis lifecycle, retrieval, Terraform draft orchestration을 소유했습니다.
- **EKS·CloudFront:** public entry는 CloudFront였고, private frontend S3/OAC와 internal ALB VPC origin을 사용했습니다.
- **Secret·권한:** External Secrets와 IRSA로 runtime Secret 및 AWS 권한 전달 경계를 분리했습니다.
- **Delivery:** immutable ECR digest를 Git desired state로 반영하고 Argo CD가 reconcile하는 GitOps 흐름을 사용했습니다.
- **Terraform:** GitHub OIDC와 protected environment의 승인형 plan/apply로 state component별 변경을 통제했습니다.
- **Observability:** CloudWatch, Application Signals, X-Ray와 bounded custom metrics를 마지막 live evidence에서 확인했습니다.

생성된 Terraform은 검토 가능한 초안이며 자동으로 `terraform apply`되지 않습니다. autoscaling, multi-replica HA, multi-region DR, generated-code 자동 배포, 실제 재배포 완료는 주장하지 않습니다.

## Lifecycle

- runtime teardown은 완료되었고, active runtime Secret은 0개입니다. 동일 Secret 이름 재사용을 잠시 막을 수 있는 pending-deletion tombstone은 1개입니다.
- bootstrap은 아직 남아 있습니다. state bucket, GitHub OIDC, Terraform plan/apply/teardown IAM 경계의 삭제는 별도 command review와 별도 승인 뒤에만 가능합니다.
- 사용자는 `DELETE_BOOTSTRAP_FOR_ZERO_RESOURCE_PROOF`를 선택했지만, **bootstrap deletion은 실행·승인되지 않았고 zero-resource proof도 완료되지 않았습니다.**
- full-zero-state 재배포 절차는 문서화되어 있으나 실행하지 않았습니다.

## 주요 문서

- [프로젝트 전체 구성 안내](docs/project-system-overview.md)
- [현재 종료 상태와 승인 경계](docs/current-operations-delivery-plan.md)
- [배포 구조와 계약](docs/deployment.md)
- [AWS 전체 삭제 runbook](docs/lifecycle/aws-teardown-runbook.md)
- [완전 삭제 후 재배포 runbook](docs/lifecycle/aws-redeploy-runbook.md)
- [runtime closure 기록](docs/lifecycle/aws-runtime-teardown-closure.md)
- [bootstrap closure inventory](docs/lifecycle/aws-bootstrap-closure-inventory.md)
- [최종 증빙·면접 가이드](docs/portfolio/final-evidence-and-interview-guide.md)
- [마지막 live 증빙](docs/portfolio/last-verified-live-evidence.md)

## 프로젝트 단계와 범위

| 단계 | 상태 |
|---|---|
| 팀 프로젝트의 서비스 목적·기초 구현 | 2024년 팀 작업 |
| 원본 및 `rdb-refactor` 재사용·Backend/RDB 정렬 | 후속 개인 고도화 |
| AWS runtime 구현과 bounded live verification | historical live evidence로 보존 |
| runtime teardown 및 independent read-only closure | complete |
| bootstrap deletion command review / execution | pending / not approved |
| full-zero-state redeployment | documented, not executed |

세부 구현과 historical evidence, lifecycle 의사결정은 위 주요 문서가 source of truth입니다.
