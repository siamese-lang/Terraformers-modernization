# Terraform State Inventory Result

## 1. Execution identity

This result records the first read-only Terraform state inventory performed for portfolio closure.

| Field | Value |
|---|---|
| Workflow | `AWS Terraform State Inventory` |
| Run ID | `29852860787` |
| Source branch | `agent/rdb-domain-realignment` |
| Source commit | `35022ccd21f2a88a0ce8728b0a834040f4b8506a` |
| AWS region | `ap-northeast-2` |
| State components inspected | `7` |
| Credential mode | GitHub OIDC through `aws-live-plan` |
| Raw state uploaded | No |
| Terraform outputs uploaded | No |
| tfvars used | No |
| Terraform plan/apply/destroy | None |
| AWS mutation | None |
| Artifact ID | `8504088933` |
| Artifact digest | `sha256:d5be71de5eb6791dbb0fc8b645cba0545678bfe2176c8ad301157309856656da` |

The workflow verified the exact AWS account and source commit before reading state objects. Every state object existed and was written by Terraform `1.15.8`.

## 2. Inventory totals

| State component | Serial | Total instances | Managed resources | Data sources | Distinct resource types |
|---|---:|---:|---:|---:|---:|
| `bootstrap` | 12 | 25 | 16 | 9 | 12 |
| `network` | 3 | 17 | 16 | 1 | 9 |
| `runtime-dependencies` | 3 | 16 | 16 | 0 | 11 |
| `stateful-dependencies` | 3 | 5 | 5 | 0 | 5 |
| `eks-runtime` | 14 | 42 | 30 | 12 | 15 |
| `frontend-delivery` | 5 | 19 | 14 | 5 | 18 |
| `rag-runtime` | 9 | 29 | 23 | 6 | 18 |
| **Total** | — | **153** | **120** | **33** | — |

The `resource_instances` value includes Terraform data sources. Teardown planning must use the **120 managed resource instances**, not the total 153 instances.

## 3. State ownership findings

### 3.1 `bootstrap`

Confirmed managed groups:

- one versioned, encrypted, private Terraform state S3 bucket;
- Terraform live-plan and live-apply IAM roles;
- state access, IAM mutation, RAG create, and Operations Visibility permission documents/attachments.

Important gap:

- no `aws_iam_openid_connect_provider` resource is present in this state;
- the GitHub OIDC provider must therefore be classified by the remaining live inventory as shared account configuration, manually bootstrapped project configuration, or a resource owned by another state;
- it must not be deleted as a project resource until ownership is proven.

### 3.2 `network`

Confirmed managed groups:

- one VPC;
- two public and two private subnets;
- one internet gateway;
- one NAT gateway and one EIP;
- public/private route tables and associations;
- one S3 gateway endpoint.

Not present:

- no Bedrock Runtime interface endpoint is represented in the current state;
- optional endpoint support in source must not be mistaken for a live resource.

### 3.3 `runtime-dependencies`

Confirmed managed groups:

- one immutable ECR repository and lifecycle policy;
- upload and result S3 buckets with versioning, encryption, and public-access blocking;
- two SQS queues;
- one Backend runtime Secrets Manager container;
- one GitHub OIDC image-publisher role and scoped policy.

Not represented in state:

- ECR image manifests and layers;
- S3 current objects, noncurrent versions, delete markers, and multipart uploads;
- SQS messages;
- the Secret value and versions.

These are `data-only` cleanup targets.

### 3.4 `stateful-dependencies`

Confirmed managed groups:

- one MariaDB RDS instance;
- one DB subnet group;
- one database security group;
- one Cognito user pool and one user-pool client.

Not represented in state:

- RDS-managed master-password Secret;
- database contents;
- manual or automated snapshots and retained backups;
- Cognito users and sessions.

These must be included in the live data and residual scan.

### 3.5 `eks-runtime`

Confirmed managed groups:

- one EKS cluster and one managed node group;
- EKS OIDC provider;
- CloudWatch Observability managed add-on;
- one CloudWatch dashboard and three metric alarms;
- Backend, External Secrets, Load Balancer Controller, EKS node/control-plane, and CloudWatch IRSA/IAM roles and policies;
- EKS cluster and Backend-origin ALB security groups.

Not represented in state:

- Kubernetes Deployments, Services, ConfigMaps, Secrets, ExternalSecrets, Ingress, namespaces, Helm releases, or Argo CD Applications;
- the internal ALB, listeners, target groups, registrations, and controller-generated rules;
- service-generated CloudWatch log groups, metrics, and X-Ray traces.

These remain the most important non-Terraform owner boundary before EKS deletion.

### 3.6 `frontend-delivery`

Confirmed managed groups:

- one CloudFront distribution;
- one CloudFront VPC origin referencing the internal ALB as a data source;
- one SPA rewrite function;
- one S3 origin access control;
- one private, versioned frontend bucket and its policy/lifecycle configuration;
- one GitHub OIDC frontend-delivery role and scoped policy.

Not represented in state:

- frontend object versions and delete markers;
- CloudFront invalidation history;
- the internal ALB itself.

The ALB must be removed through its Kubernetes Ingress owner after CloudFront no longer references it.

### 3.7 `rag-runtime`

Confirmed managed groups:

- one private AOSS vector collection;
- AOSS encryption, network, and data-access policies;
- one AOSS VPC endpoint;
- one private CodeBuild ingestion project;
- Backend reader, GitHub ingestion dispatcher, and CodeBuild writer IAM boundaries;
- one private, versioned corpus bucket;
- AOSS and CodeBuild security groups plus two scoped ingress rules.

Not represented in state:

- the physical AOSS index and vector documents;
- CodeBuild run history;
- corpus object versions, receipts, and multipart uploads.

The committed corpus remains the recreation source; the vector index is reproducible service data.

## 4. Confirmed Terraform teardown boundary

Terraform state now proves the following high-level runtime destroy order is structurally valid:

```text
frontend-delivery
  -> Kubernetes/GitOps owners and controller-generated ALB
  -> rag-runtime
  -> eks-runtime
  -> stateful-dependencies
  -> runtime-dependencies
  -> network
  -> bootstrap last
```

This order is not yet approval to run destroy. It remains conditional on the live non-Terraform inventory and retention decisions.

## 5. Remaining Closure Gate 1 scope

Terraform state inventory is complete. The remaining read-only inventory is limited to the following items:

1. **Kubernetes and GitOps owners**
   - Argo CD Applications and Helm release;
   - Backend Deployment, Service, ConfigMap, ServiceAccount, Ingress;
   - External Secrets Operator, SecretStore, ExternalSecret, generated Secret;
   - AWS Load Balancer Controller and related ServiceAccount;
   - temporary Jobs/Pods and project namespaces.

2. **Controller-generated AWS resources**
   - internal ALB;
   - listeners and listener rules;
   - target groups and target registrations;
   - generated security-group rules and load-balancer ENIs.

3. **Mutable data and service-generated resources**
   - ECR image count;
   - S3 object versions, delete markers, and multipart uploads per bucket;
   - SQS message counts;
   - active and pending-deletion Secrets;
   - RDS snapshots, retained backups, and managed credential Secret;
   - Cognito users;
   - AOSS index/document count and CodeBuild run state;
   - CloudWatch log groups and retention settings.

4. **External configuration and bootstrap ownership**
   - GitHub OIDC provider ownership;
   - GitHub Environment, variable, and encrypted-secret names;
   - approval rules required for teardown and later redeployment.

No new broad discovery or architecture review is required. Closure Gate 1 completes when these four groups are recorded in `aws-resource-inventory.md` with delete owner, prerequisite, retention decision, and residual check.

## 6. Safety conclusions

- All seven expected state objects exist.
- No raw state, outputs, tfvars, or saved plan was retained in repository evidence.
- The inventory made no AWS change.
- Terraform controls 120 managed resource instances, but it does not control all data and controller-generated resources.
- `terraform destroy` alone cannot prove complete deletion.
- The GitHub OIDC provider must not be deleted until its ownership is resolved.
- EKS must not be destroyed before Kubernetes owners and the internal ALB are removed.