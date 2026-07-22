# Terraform Destroy Plan Review

## 1. Review scope

This document records the completed read-only destroy-plan review for all seven Terraform state components.

Source identities:

```text
six_runtime_and_network_plans_commit=36a62f8e0368ce22d19a54cca526fdfb85abffd9
foundation_replan_commit=7f6f32a4561dab68658bc9307ae83a5733b3bed6
aws_account=024863981627
aws_region=ap-northeast-2
terraform_version=1.15.8
terraform_apply_executed=false
terraform_destroy_executed=false
```

The workflows retained only sanitized addresses, action/type counts, tfvars and binary-plan hashes, and summary files. Raw plan JSON, binary plans, tfvars, outputs, changed values, and state were not uploaded.

## 2. Final result

| Stage | Run ID | Source commit | Result | Managed deletes | Update/create/replacement/import | High-cost references |
|---|---:|---|---|---:|---|---|
| `frontend-delivery` | `29856519775` | `36a62f8e…` | PASS | 14 | 0 | CloudFront distribution |
| `rag-runtime` | `29856522168` | `36a62f8e…` | PASS | 23 | 0 | AOSS collection |
| `eks-runtime` | `29856524234` | `36a62f8e…` | PASS | 30 | 0 | EKS cluster and node group |
| `stateful-dependencies` | `29856526566` | `36a62f8e…` | PASS | 5 | 0 | RDS instance |
| `runtime-dependencies` | `29856528584` | `36a62f8e…` | PASS | 16 | 0 | none |
| `network` | `29856530899` | `36a62f8e…` | PASS | 16 | 0 | NAT gateway |
| `foundation` | `29858008935` | `7f6f32a4…` | PASS | 16 | 0 | state bucket and execution roles |
| **Total** | — | — | **PASS** | **120** | **0** | — |

All seven plans passed the destroy-only contract:

```text
managed_non_delete_action_count=0
data_source_non_read_action_count=0
update_resource_count=0
replacement_resource_count=0
destroy_only_contract=passed
```

The 120 managed delete actions exactly reconcile to the 120 managed resource instances recorded by the read-only Terraform state inventory. The remaining 33 state instances are data sources and are not destruction targets.

## 3. Saved plan hashes

The binary plans themselves were removed before artifact upload. These hashes identify the reviewed runner-local plans only and cannot be applied later.

| Stage | Binary plan SHA-256 | tfvars SHA-256 |
|---|---|---|
| `frontend-delivery` | `0f3e91677fea09b269d494dc0fd0d6d285c586752821832d385bdb07b13b853a` | `4f4932959a1c924f7a92e93f48def9c937c163aac278bbcd9640fed08c9e05a4` |
| `rag-runtime` | `f745fb8fc8f494d95763eda3f947fbb52006bb3d1df339176a8f0eb3d8de3166` | `40e793f17e6ead36489b819849796b25e266e2988761ac85c18e311d33e05a53` |
| `eks-runtime` | `66d116f64133fbbb723dbe0bd97a3f9de53b97b3a664a1e9870d72d24a06fb7c` | `a6dba7081f4363efffdda235f80ddd96e0074b1ed5934e4efe1841c85bf3a5c0` |
| `stateful-dependencies` | `7c9489a83ba3b93113f2d4d08d4ed8bcad50189f025c872e37105e84dde65862` | `6e4ab5d65ac5cb8a3969f0440501ab58db79e829c2988ee6e4fe75106b5573e1` |
| `runtime-dependencies` | `4c92da27f477d649061c7dcc2000e39d98f16419f9acbce090a46d0a033b4569` | `96c6ba2fd1c4091fb9130cce1dc0cd6ba5ee771c6ac44c70ca15c9cb1c8e67bc` |
| `network` | `96bc2677713a1dff1971563df558f96dc7743444990e750dc76d2fcb394f097c` | `f53fe8179c601f3b455bb2cccee418c085dbebcec90344a96010e6a0cc4d064a` |
| `foundation` | `e4694d21f27e2b777d610a2661f991e9b63f211fe16010cd30cb547c88744f43` | `c42af1c7dec9272b13339155116831b4324ee8ea1e608cc7249a4cfd4385d7ea` |

## 4. Stage review

### 4.1 `frontend-delivery` — 14 deletes

Confirmed resource groups:

- CloudFront distribution;
- CloudFront VPC origin;
- SPA rewrite function;
- origin access control;
- private frontend bucket and its versioning, encryption, lifecycle, policy, ownership and public-access controls;
- frontend-delivery IAM role, policy and attachment.

Required before an approved apply:

1. freeze frontend delivery;
2. remove all 70 object versions and 30 delete markers;
3. allow CloudFront disable/delete propagation;
4. confirm the VPC origin no longer references the internal ALB before deleting the Ingress.

### 4.2 `rag-runtime` — 23 deletes

Confirmed resource groups:

- private AOSS collection, VPC endpoint, encryption/network/data policies;
- CodeBuild corpus ingestion project;
- corpus bucket and controls;
- Backend reader, GitHub dispatcher and CodeBuild writer IAM boundaries;
- AOSS and CodeBuild security groups and scoped ingress rules.

Required before an approved apply:

1. confirm no CodeBuild ingestion is running;
2. remove all seven corpus-bucket object versions;
3. accept deletion of the physical index and 128 vector documents;
4. stop Backend retrieval before deleting the collection and endpoint.

### 4.3 `eks-runtime` — 30 deletes

Confirmed resource groups:

- EKS cluster, managed node group and EKS OIDC provider;
- CloudWatch Observability add-on;
- dashboard and three alarms;
- six IAM roles, three policies, one inline policy and ten attachments;
- two security groups.

Required before an approved apply:

1. stop Argo CD reconciliation;
2. remove the Backend Application resources;
3. delete the Ingress and wait for the internal ALB, target group, listeners, rules, generated security-group rules and ENIs to disappear;
4. remove ExternalSecret/SecretStore/generated Secret and operator releases;
5. remove AWS Load Balancer Controller, External Secrets and Argo CD before cluster deletion;
6. delete service-generated project log groups after final evidence retention.

The EKS plan is structurally valid but must not be applied while Kubernetes and controller owners remain.

### 4.4 `stateful-dependencies` — 5 deletes

Confirmed resource groups:

- MariaDB RDS instance;
- DB subnet group and security group;
- Cognito user pool and client.

Required before an approved apply:

1. stop Backend database access;
2. retain the decision to skip a final snapshot;
3. accept removal of the automated backup and RDS-managed master Secret;
4. delete the state-external legacy `terraformers-modernization-live-smoke-users` pool separately.

### 4.5 `runtime-dependencies` — 16 deletes

Confirmed resource groups:

- ECR repository and lifecycle policy;
- upload/result buckets and controls;
- two current SQS queues;
- Backend runtime Secret container;
- image-publisher IAM role, policy and attachment.

Required before an approved apply:

1. stop Backend and ExternalSecret reconciliation;
2. delete all 20 ECR images;
3. purge 35 upload-bucket versions and 21 result-bucket versions;
4. force-delete the runtime Secret only after the generated Kubernetes Secret path is stopped;
5. delete the two state-external `live-smoke` SQS queues separately.

### 4.6 `network` — 16 deletes

Confirmed resource groups:

- VPC;
- two public and two private subnets;
- NAT gateway and EIP;
- internet gateway;
- three route tables, four associations and S3 gateway endpoint.

Required before an approved apply:

1. complete frontend, RAG, EKS, stateful and runtime dependency deletion;
2. confirm no ALB, CloudFront VPC origin, AOSS endpoint, RDS, EKS, interface endpoint, security group or project ENI remains;
3. delete network only after the residual scan shows no dependent resource.

### 4.7 `foundation` — 16 deletes

Confirmed resource groups:

- Terraform state bucket and its policy, public-access block, ownership, encryption and versioning resources;
- Terraform live-plan and live-apply roles;
- four inline policies;
- three role-policy attachments;
- Operations Visibility create policy.

The successful plan used the explicitly reviewed runner-only override:

```text
foundation_prevent_destroy_override=true
foundation_override_committed=false
```

Required before an approved bootstrap teardown:

1. complete all runtime teardown and pass the runtime residual scan;
2. preserve an independent AWS administrator or CloudShell identity;
3. export state metadata only if explicitly retained;
4. purge 175 state-bucket object versions and 126 delete markers;
5. remove the project-dedicated GitHub OIDC provider separately because it is outside Terraform state;
6. delete the foundation roles and state bucket in an order that does not strand the final operation.

Foundation is not part of runtime teardown and remains the final teardown phase.

## 5. Foundation safeguard and controlled planning exception

The first foundation run `29856533560` was intentionally blocked by the committed state bucket safeguard:

```hcl
resource "aws_s3_bucket" "terraform_state" {
  lifecycle {
    prevent_destroy = true
  }
}
```

The safeguard remains committed. Run `29858008935` created a temporary override only in the GitHub-hosted runner checkout, generated and reviewed the plan, recorded the override boundary, and removed the file before artifact upload. No source safeguard was weakened and no plan was applied.

The same explicit exception will be required for final bootstrap execution, but only after runtime residual proof and from an execution path that cannot delete its own final credentials prematurely.

## 6. Closure Gate 3 result

Status: **COMPLETE**

Completed:

- all seven state-component plans reviewed;
- 120 managed deletes reconciled to the state inventory;
- no create, update, replacement or import action;
- delete-only contract passed for every stage;
- all non-Terraform cleanup prerequisites assigned to execution phases;
- foundation reviewed and fixed as the final phase;
- no resource deletion executed.

The reviewed plans are not reusable apply artifacts. Runtime execution must create a fresh saved plan inside the approved destructive job and immediately apply that exact plan after rechecking the stage contract and prerequisites.

## 7. Next boundary

Closure Gate 4 may now design a separately approved runtime teardown workflow. The workflow must:

- exclude `foundation`;
- perform one exact runtime stage per dispatch;
- require explicit stage confirmation and exact integration commit;
- run precondition checks for non-Terraform owners and mutable data;
- create a fresh destroy plan, enforce the reviewed delete-only count/address contract, and apply the saved plan in the same job;
- verify post-destroy state and service-specific residuals;
- stop at the first failing stage;
- never infer that a successful Terraform apply removed state-external data or controller-generated resources.

No runtime deletion is authorized by this document alone.