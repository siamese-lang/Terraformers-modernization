# AWS Resource Inventory for Closure

## 1. Status and authority

Status: **Closure Gate 1 complete — historical pre-teardown inventory**

> **Closure notice:** This document preserves the authoritative pre-teardown owner and resource inventory captured at Closure Gate 1. Its live counts describe the environment before runtime teardown and are historical, not current AWS resource counts.
>
> Runtime teardown and independent runtime closure verification were subsequently completed. For the current state and next action, use [closure-progress.md](closure-progress.md) and [current-operations-delivery-plan.md](../current-operations-delivery-plan.md).

This document is the authoritative historical owner and deletion inventory for removing and later recreating Terraformers-modernization.

Detailed evidence:

- `docs/lifecycle/aws-terraform-state-inventory-result.md`;
- `docs/lifecycle/kubernetes-and-alb-inventory-result.md`;
- `docs/lifecycle/final-data-and-owner-inventory-result.md`;
- `docs/portfolio/last-verified-live-evidence.md`.

The inventory was assembled from read-only Terraform state, Kubernetes, Argo CD, AWS, and GitHub inspections. No resource was mutated.

## 2. Management boundaries

| Classification | Meaning | Canonical delete owner |
|---|---|---|
| `terraform` | Resource is represented in one remote Terraform state | Reviewed destroy plan and later approved apply |
| `gitops` | Resource is reconciled from Git by Argo CD | Suspend/delete Argo CD Application and managed object |
| `kubernetes-operator` | Resource is owned by Helm, a controller, or custom resource | Remove custom resource/release in dependency order |
| `controller-generated` | AWS resource is generated from a Kubernetes owner | Delete owner object, then verify AWS reconciliation |
| `data-only` | Mutable contents are outside Terraform state | Bounded service API cleanup |
| `legacy-residual` | Project resource from live-smoke work but outside current state | Explicit cleanup and residual verification |
| `bootstrap` | Resource required to finish Terraform teardown | Delete last |
| `external-config` | GitHub configuration outside AWS | Retain or remove as a separate decision |

Terraform state is necessary but not sufficient for zero-resource proof.

The Gate 1 inventory observed five Terraformers trusting roles before runtime teardown. The later bootstrap-closure inventory observed three remaining bootstrap roles. This is lifecycle convergence after runtime-role removal, not conflicting OIDC ownership data.

## 3. Terraform state summary

| State component | Total instances | Managed resources | Data sources | Main responsibility |
|---|---:|---:|---:|---|
| `bootstrap` | 25 | 16 | 9 | State bucket and Terraform plan/apply IAM boundaries |
| `network` | 17 | 16 | 1 | VPC, subnets, routes, NAT/IGW, S3 endpoint |
| `runtime-dependencies` | 16 | 16 | 0 | ECR, upload/result buckets, SQS, runtime Secret, image role |
| `stateful-dependencies` | 5 | 5 | 0 | RDS and current Cognito pool/client |
| `eks-runtime` | 42 | 30 | 12 | EKS, node group, add-on, IRSA, dashboard and alarms |
| `frontend-delivery` | 19 | 14 | 5 | CloudFront, VPC origin, frontend bucket and delivery role |
| `rag-runtime` | 29 | 23 | 6 | AOSS, CodeBuild, corpus bucket, IAM and private network |
| **Total** | **153** | **120** | **33** | — |

Destroy planning uses the 120 managed resource instances, not the 153 total instances.

## 4. Complete resource matrix

| Resource group | Class | State/owner | Confirmed live state | Delete prerequisite | Delete owner | Recreation source | Retention decision | Residual proof |
|---|---|---|---|---|---|---|---|---|
| Terraform state bucket | bootstrap/data-only | `bootstrap` plus external final procedure | versioned; 175 versions and 126 delete markers | all runtime states and residual checks complete | independent administrator/CloudShell last | foundation bootstrap root | purge all versions last; no repository copy | bucket, versions, markers and locks absent |
| GitHub OIDC provider | bootstrap | outside state | 1 provider; all 5 trusting roles are Terraformers roles | all GitHub AWS work and roles complete | independent administrator/CloudShell last | minimal bootstrap procedure | delete last | provider absent |
| Terraform plan/apply roles | bootstrap/terraform | `bootstrap` | 2 execution roles plus scoped policies | all runtime operations complete | bootstrap destroy/final administrator | foundation root | none | roles/policies absent |
| VPC, subnets, routes, NAT, IGW | terraform | `network` | one VPC, 2 public + 2 private subnets, NAT/IGW and routes | EKS, RDS, AOSS endpoint, ALB, CloudFront VPC origin and ENIs absent | network destroy | network root | none | VPC and dependent network objects absent |
| S3 gateway/AOSS interface endpoints | terraform | `network` and `rag-runtime` | one S3 gateway endpoint and one AOSS VPC endpoint | dependent services removed | corresponding state destroy | Terraform roots | none | endpoints absent |
| ECR repository/images | terraform + data-only | `runtime-dependencies` | 1 repository, 20 images | Backend stopped and digest evidence frozen | image purge then runtime destroy | Terraform root + image workflow | retain digest string only | repository/images absent |
| Upload S3 bucket | terraform + data-only | `runtime-dependencies` | versioned; 35 versions | Backend stopped | purge versions then runtime destroy | Terraform root + application | delete all | bucket/versions absent |
| Result S3 bucket | terraform + data-only | `runtime-dependencies` | versioned; 21 versions | final evidence frozen | purge versions then runtime destroy | Terraform root + application | retain sanitized summaries only | bucket/versions absent |
| Frontend S3 bucket | terraform + data-only | `frontend-delivery` | versioned; 70 versions, 30 markers | frontend delivery frozen, CloudFront removal ready | purge versions then frontend destroy | Terraform root + delivery workflow | rebuildable; delete all | bucket/versions/markers absent |
| Corpus S3 bucket | terraform + data-only | `rag-runtime` | versioned; 7 versions | no CodeBuild ingestion running | purge versions then RAG destroy | committed corpus + workflow | retain corpus in Git only | bucket/versions absent |
| Current SQS queues | terraform | `runtime-dependencies` | `terraformers-ai-log`, `terraformers-terraform-log`; zero messages | Backend stopped | runtime destroy | Terraform root | none | queues absent |
| Legacy live-smoke SQS queues | legacy-residual | outside state | 2 queues; zero messages | none after workload stop | explicit residual cleanup | not recreated | none | names absent |
| Backend runtime Secret | terraform + data-only | `runtime-dependencies` and ExternalSecret | active; generated Kubernetes Secret Ready | Backend stopped and reconciliation removed | Kubernetes owner cleanup then force-delete Secret | Terraform + initialization procedure | retain names/source only | active/pending Secret absent |
| RDS managed master Secret | data-only | RDS service | 1 active managed Secret | RDS deletion | RDS lifecycle | RDS managed password | never retain value | managed Secret absent |
| RDS instance and DB network | terraform + stateful data | `stateful-dependencies` | 1 instance; deletion protection off; 0 manual snapshots; 1 automated backup record | Backend stopped | stateful destroy | Terraform + Flyway | skip final snapshot; retain no backups | DB, subnet group, SG, backups and Secret absent |
| Current Cognito pool/client | terraform + data-only | `stateful-dependencies` | `terraformers-modernization-dev-users`; zero users | frontend/backend stopped | stateful destroy | Terraform + test-user procedure | none | pool/client absent |
| Legacy live-smoke Cognito pool | legacy-residual | outside state | `terraformers-modernization-live-smoke-users`; zero users | none after traffic stop | explicit residual cleanup | not recreated | none | pool absent |
| EKS cluster/node group/add-ons | terraform | `eks-runtime` | cluster, one node group, CloudWatch add-on | all Kubernetes owners and generated ALB removed | EKS destroy | EKS root | none | cluster/node group/add-ons absent |
| EKS/Backend/controller IRSA | terraform + Kubernetes identity | `eks-runtime` | 5 IRSA ServiceAccounts; roles in state | corresponding workloads/controllers removed | Kubernetes cleanup then EKS destroy | Terraform + manifests | none | SAs/roles/policies absent |
| Argo CD | kubernetes-operator/gitops | Helm release | 1 StatefulSet Ready; 4 Deployments; Backend Application Synced/Healthy | auto-sync suspended and managed app removed | Application then Helm removal | pinned chart/manifests | retain Git history | namespace/release/resources absent |
| Backend workload | gitops | Argo CD Application | 1 Deployment, 1 Service, 1 Ingress; Pod Ready, restart 0 | final runtime evidence frozen | Argo CD/Application owner | GitOps overlay + digest workflow | retain digest evidence | objects absent |
| External Secrets | kubernetes-operator | Helm + CRs | 1 operator release, 1 ExternalSecret Ready, 1 SecretStore, generated Secret present | Backend stopped | CRs/generated Secret then Helm removal | pinned chart/manifests | never retain Secret values | all CRs/Secret/release absent |
| AWS Load Balancer Controller | kubernetes-operator | Helm + Ingress | controller `1/1` | CloudFront no longer references ALB | Ingress reconciliation then Helm removal | chart/IRSA/manifests | none | controller/release absent |
| Internal ALB dependencies | controller-generated | Backend Ingress | 1 internal ALB, 1 listener, 2 rules, 1 target group, 2 SGs, 2 ENIs, 1 healthy target | CloudFront VPC origin removed | delete Ingress and wait | Ingress/controller | none | all ALB dependencies absent |
| CloudFront delivery | terraform | `frontend-delivery` | 1 distribution, VPC origin, function, OAC | delivery frozen; distribution deletion semantics satisfied | frontend destroy | Terraform + frontend workflow | retain sanitized domain/UI evidence only | distribution/origins absent |
| AOSS collection and endpoint | terraform | `rag-runtime` | 1 ACTIVE collection and private endpoint | Backend and ingestion stopped | RAG destroy | Terraform root | none | collection/policies/endpoint absent |
| AOSS index/documents | data-only | ingestion workflow | 128 verified corpus-v2 documents | no ingestion build running | collection/index cleanup | corpus v2 + ingestion workflow | retain corpus/receipt only | index/documents absent |
| CodeBuild ingestion | terraform | `rag-runtime` | 1 project; 0 active builds | none after ingestion freeze | RAG destroy | Terraform root | retain run IDs only | project/role absent |
| CloudWatch dashboard/alarms | terraform | `eks-runtime` | 1 dashboard and 3 alarms | final evidence frozen | EKS destroy | Terraform root | summaries only | dashboard/alarms absent |
| CloudWatch log groups | data-only/service-generated | AWS services | 8 groups, all without retention; 529,613,946 bytes | evidence frozen and workloads stopped | explicit log cleanup | runtime recreates | delete all | project log groups absent |
| X-Ray traces | service-retained | X-Ray | verified traces; no separate project destroy resource | workloads stopped | service retention expiry | runtime recreates | retain sanitized counts only | no project-owned X-Ray resource |
| GitHub environments/variables/secrets | external-config | GitHub | 5 environments; variable/secret names inventoried | none | retain outside AWS teardown | redeploy runbook | retain for redeployment | documented retained state |

## 5. Canonical deletion order

```text
1. Freeze final evidence and delivery
2. Remove CloudFront/VPC-origin dependency
3. Suspend Argo CD and remove Backend Application resources
4. Delete Ingress and wait for ALB/listener/rules/TG/SG/ENI cleanup
5. Remove ExternalSecret/SecretStore/generated Secret and operators
6. Purge frontend bucket and destroy frontend-delivery
7. Purge corpus data and destroy rag-runtime
8. Destroy eks-runtime
9. Delete current and legacy Cognito resources; destroy stateful-dependencies
10. Purge ECR/application buckets, force-delete runtime Secret, remove legacy queues, destroy runtime-dependencies
11. Destroy network after all ENIs/endpoints are absent
12. Verify runtime residual count is zero
13. Remove bootstrap roles, project OIDC provider, state versions and state bucket last
```

The frontend Terraform destroy plan may need to be created before Kubernetes owner removal but applied in the reviewed order required to release the CloudFront VPC-origin dependency. The exact split is determined in Closure Gate 3.

## 6. Retention contract

- ECR: delete all 20 images; retain final digest string only.
- S3: delete all 308 versions and 156 delete markers; state bucket last.
- RDS: skip final snapshot and retain no automated/manual backup.
- Secrets: retain no value; final runtime Secret deletion uses force deletion to avoid name-reuse delay.
- Cognito: delete current and legacy-smoke pools; retain no user/token data.
- AOSS: delete all data and collection; recreate from committed corpus v2.
- CloudWatch: retain sanitized evidence summaries, delete all eight project log groups.
- GitHub configuration: retain for future redeployment.

This contract guides planning. It does not authorize deletion.

## 7. Closure Gate 1 completion

Closure Gate 1 is complete because:

- all seven state components are accounted for;
- every Kubernetes object group has an owner and deletion order;
- every controller-generated AWS resource has a Kubernetes owner;
- every data-only and legacy residual resource has a cleanup decision;
- bootstrap resources are separated from runtime resources;
- GitHub OIDC ownership is resolved as project-dedicated external bootstrap;
- no unexplained project resource remains;
- this inventory can drive teardown and redeployment without relying on memory.

Runtime destroy planning and execution are complete. The current boundary is additional IAM/EKS-OIDC read-only classification, exact bootstrap deletion command review, and separate execution approval. This historical inventory does not authorize a mutation.
