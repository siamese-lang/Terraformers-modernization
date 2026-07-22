# Runtime Teardown Execution

## 1. Purpose

This document describes Closure Gate 4: removing the Terraformers runtime environment one reviewed stage at a time while preserving the bootstrap state bucket, GitHub OIDC provider, Terraform plan/apply roles, and final administrative recovery path.

The runtime workflow is intentionally separate from:

- the read-only destroy-plan workflow;
- the existing limited `aws-live-apply` role;
- final foundation/state/OIDC deletion.

Merging the workflow does not authorize a run. Every stage requires a new GitHub Environment approval and an exact stage-specific confirmation.

## 2. Why a separate teardown role is required

The existing `terraformers-live-terraform-apply` role has ReadOnlyAccess plus narrowly scoped create/update permissions used during deployment. It does not have the delete permissions required for CloudFront, AOSS, EKS, RDS, S3, ECR, IAM, network, and controller cleanup.

The teardown path therefore uses a state-external temporary role:

```text
terraformers-live-teardown
```

The role:

- trusts only `repo:siamese-lang/Terraformers-modernization:environment:aws-live-teardown`;
- has ReadOnlyAccess for inventory and Terraform refresh;
- has an inline project teardown policy;
- does not receive AdministratorAccess;
- is not managed by a runtime Terraform state that it must destroy;
- remains until runtime residual verification is complete;
- is deleted later from an independent CloudShell/administrator identity during bootstrap closure.

The bootstrap script is:

```text
scripts/teardown/bootstrap_runtime_teardown_role.sh
```

Running that script is an AWS mutation and requires explicit approval. It must be run from AWS CloudShell or another independent administrator session, not from the role it creates.

## 3. GitHub Environment

Create a protected GitHub Environment named:

```text
aws-live-teardown
```

Required variables:

```text
AWS_REGION
AWS_ROLE_TO_ASSUME
AWS_TERRAFORM_STATE_BUCKET
AWS_TERRAFORM_STATE_PREFIX
```

`AWS_ROLE_TO_ASSUME` must be the ARN of `terraformers-live-teardown`.

Required encrypted secrets are the same private tfvars already used by the plan environment:

```text
AWS_LIVE_NETWORK_TFVARS_B64
AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64
AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64
AWS_LIVE_EKS_TFVARS_B64
AWS_LIVE_FRONTEND_TFVARS_B64
AWS_LIVE_RAG_TFVARS_B64
```

Do not add the foundation tfvars to this environment. Runtime teardown cannot select or delete foundation.

Recommended protection:

- required reviewer;
- prevent self-review where available;
- no deployment branch broader than the integration branch;
- keep the environment disabled or remove the role after teardown.

## 4. Execution workflow

Workflow:

```text
.github/workflows/aws-runtime-teardown.yml
```

Configuration and contract helper:

```text
config/runtime-teardown-stages.json
scripts/teardown/runtime_teardown.py
```

Each dispatch performs exactly one stage. Global concurrency prevents two teardown stages from running together.

Required inputs:

- exact integration commit;
- exact AWS account;
- exact stage;
- reviewed maximum delete count;
- exact confirmation string;
- `execute_runtime_teardown=true`.

The workflow creates a fresh saved destroy plan and applies that exact plan in the same job. It never uses `terraform destroy` and never reuses the earlier review plan binary.

A recovery run may contain fewer delete actions than the first review because a prior apply partially succeeded. It is accepted only when every remaining address is a subset of the original reviewed address set. New addresses, creates, updates, replacements, imports, and non-read data actions are rejected.

## 5. Stage order and confirmations

| Order | Stage | Reviewed maximum deletes | Exact confirmation |
|---:|---|---:|---|
| 1 | `frontend-delivery` | 14 | `DESTROY_REVIEWED_FRONTEND_DELIVERY_14` |
| 2 | `kubernetes-owners` | 0 | `DESTROY_REVIEWED_KUBERNETES_OWNERS_0` |
| 3 | `rag-runtime` | 23 | `DESTROY_REVIEWED_RAG_RUNTIME_23` |
| 4 | `eks-runtime` | 30 | `DESTROY_REVIEWED_EKS_RUNTIME_30` |
| 5 | `stateful-dependencies` | 5 | `DESTROY_REVIEWED_STATEFUL_DEPENDENCIES_5` |
| 6 | `runtime-dependencies` | 16 | `DESTROY_REVIEWED_RUNTIME_DEPENDENCIES_16` |
| 7 | `network` | 16 | `DESTROY_REVIEWED_NETWORK_16` |

The workflow reads prior remote states and rejects a stage when any required predecessor still has a managed resource instance.

## 6. Stage behavior

### 6.1 `frontend-delivery`

- applies a runner-only `force_destroy=true` override to the frontend bucket;
- removes all frontend object versions and delete markers through the provider;
- deletes the CloudFront distribution, function, OAC, VPC origin, bucket, and delivery IAM resources;
- verifies the frontend bucket and Terraformers CloudFront VPC origin are absent.

The override is removed from the runner checkout and is never committed.

### 6.2 `kubernetes-owners`

This is not a Terraform stage.

- temporarily grants the teardown role EKS cluster-admin access through an EKS access entry;
- disables and deletes the Backend Argo CD Application;
- deletes the Backend Ingress and waits for the internal ALB to disappear;
- deletes the exact ExternalSecret, SecretStore, and generated Secret;
- uninstalls AWS Load Balancer Controller, External Secrets, and Argo CD;
- deletes the runtime, external-secrets, and argocd namespaces;
- removes the temporary EKS access entry;
- verifies Terraformers ALB and target groups are absent;
- writes a non-sensitive completion marker under the Terraform state prefix.

Marker:

```text
<state-prefix>/closure/kubernetes-owners.json
```

The later EKS stage requires this marker in addition to an empty frontend and RAG state dependency chain.

### 6.3 `rag-runtime`

- rejects execution while a corpus CodeBuild job is running;
- applies a runner-only corpus bucket `force_destroy=true` override;
- deletes the AOSS collection, policies, VPC endpoint, CodeBuild project, corpus bucket, RAG IAM, and security resources;
- verifies the corpus bucket, ingestion project, and collection are absent.

The committed corpus remains the recreation source.

### 6.4 `eks-runtime`

- requires the Kubernetes-owner completion marker;
- refuses to continue while a Terraformers ALB remains;
- deletes the EKS add-on, cluster, node group, EKS OIDC provider, IRSA/IAM, dashboard, alarms, and security groups;
- deletes project CloudWatch log groups after the cluster is gone;
- verifies the cluster and project log groups are absent.

### 6.5 `stateful-dependencies`

- requires EKS state to be empty and no Terraformers EKS cluster to remain;
- applies runner-only disposable-environment RDS settings:
  - `skip_final_snapshot=true`;
  - `delete_automated_backups=true`;
  - deletion protection disabled;
- deletes RDS and the current Cognito pool/client;
- separately deletes the legacy `terraformers-modernization-live-smoke-users` pool;
- verifies no Terraformers-modernization Cognito pool remains.

### 6.6 `runtime-dependencies`

- applies runner-only `force_delete`/`force_destroy` settings for ECR and the two versioned application buckets;
- sets the runtime Secret recovery window to zero;
- deletes the current ECR, upload/result buckets, SQS queues, Secret container, and image-publisher IAM resources;
- separately deletes the two state-external live-smoke queues;
- waits for the runtime Secret to disappear from active and planned-deletion inventory.

### 6.7 `network`

- requires frontend, RAG, EKS, stateful, and runtime dependency states to be empty;
- verifies no Terraformers EKS, RDS, AOSS collection, CloudFront VPC origin, or ALB remains;
- deletes VPC, subnets, routes, gateways, NAT/EIP, and S3 gateway endpoint;
- verifies no project-tagged VPC remains.

## 7. Runner-only overrides

The repository retains protective defaults. The execution job writes temporary override files only after exact stage approval.

| Stage | Temporary override |
|---|---|
| frontend | bucket `force_destroy=true` |
| RAG | corpus bucket `force_destroy=true` |
| stateful | no final snapshot, delete automated backups, deletion protection off |
| runtime | ECR `force_delete`, buckets `force_destroy`, Secret immediate deletion |

Every artifact records:

```text
runner_override=<name>
runner_override_committed=false
```

## 8. Evidence and sensitive-data boundary

Allowed evidence:

- stage and source commit;
- expected/reviewed/actual delete count;
- sanitized address/action summary;
- binary-plan and tfvars hashes;
- prior-state managed counts;
- post-destroy managed count;
- residual check status;
- runner override name and non-committed status.

Forbidden evidence:

- raw state;
- tfvars;
- saved plan;
- raw plan JSON;
- Secret values;
- kubeconfig;
- source images, prompts, retrieved content, or generated Terraform.

## 9. Failure and restart

When a stage fails:

1. stop; do not dispatch the next stage;
2. inspect the first failing owner or AWS action;
3. do not broaden permissions without identifying the exact missing action/resource;
4. rerun only the same stage after correction;
5. allow the state-aware address subset contract to represent partial success;
6. verify state and service residuals before proceeding.

Do not rerun completed stages for reassurance.

## 10. Boundary after runtime completion

Runtime completion does not delete:

- Terraform state bucket and object versions;
- live-plan/live-apply roles;
- teardown role;
- project GitHub OIDC provider;
- GitHub Environments, variables, or encrypted secrets.

A full runtime residual scan must pass before Closure Gate 5 creates a separate bootstrap teardown procedure. The teardown role cannot delete itself and must be removed from an independent administrator identity.
