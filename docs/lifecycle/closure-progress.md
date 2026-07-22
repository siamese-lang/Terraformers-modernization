# Portfolio Closure Progress

This file records the current completion point for `docs/current-operations-delivery-plan.md`. A new conversation must read this file after the controlling plan and `docs/project-system-overview.md`, then resume from the first incomplete gate.

Last live inventory/parity revision:

```text
b3e3a672dc65c7a712a20459b3d8f1c31ca62861
```

Later documentation-only or plan-only commits do not require repeated browser or telemetry testing unless the runtime contradicts the recorded evidence.

## Closure Gate 1 - Read-only live inventory

Status: **COMPLETE**

Completed evidence:

- `docs/lifecycle/aws-terraform-state-inventory-result.md`;
- `docs/lifecycle/kubernetes-and-alb-inventory-result.md`;
- `docs/lifecycle/final-data-and-owner-inventory-result.md`;
- completed matrix in `docs/lifecycle/aws-resource-inventory.md`.

Confirmed scope:

- 7/7 remote Terraform states;
- 153 state instances: 120 managed resources and 33 data sources;
- current GitOps and Backend runtime digest parity;
- Argo CD, External Secrets, and AWS Load Balancer Controller owners;
- internal ALB and all known listener/rule/target/SG/ENI dependencies;
- ECR image count;
- five versioned S3 buckets and all version/delete-marker counts;
- current and legacy-smoke SQS/Cognito resources;
- active Secrets, RDS managed Secret, snapshots/backups;
- AOSS/CodeBuild data and activity;
- CloudWatch log groups and stored bytes;
- GitHub OIDC provider ownership;
- GitHub Environment, variable, and encrypted-secret names.

Key conclusions:

- GitHub OIDC is outside Terraform state but project-dedicated; delete it last from an independent identity.
- Two `live-smoke` SQS queues and one `live-smoke` Cognito pool are legacy residuals outside current state.
- `terraform destroy` alone cannot remove all project resources or data.
- EKS cannot be destroyed until Argo CD, Ingress, External Secrets, controllers, and controller-generated ALB resources are removed.
- all data and retention decisions are explicit.

No inventory command mutated AWS, Kubernetes, Argo CD, Terraform, images, or GitHub configuration.

## Closure Gate 2 - Evidence freeze and interview record

Status: **COMPLETE**

Completed:

- full system overview in `docs/project-system-overview.md`;
- expanded interview guide with seven representative engineering difficulties;
- immutable Backend image digest frozen;
- real browser analysis success designated as the final bounded analysis result;
- Application Signals, X-Ray, AOSS, and custom metric results frozen;
- current Argo CD revision, desired image, Pod runtime image ID, readiness, and zero restart state recorded;
- teardown/redeploy decisions and explicit non-claims documented;
- no additional raw screenshot or log dump is required for the portfolio evidence set.

Final bounded result:

```text
analysis_outcomes=succeeded started
aoss_metric_series=1
application_signals_latency_series=78
xray_trace_count=181
xray_terraformers_service_count=2
operations_visibility_result=PASS
```

A final minimal parity read may be performed immediately before destructive execution only if additional runtime-affecting source changes merge.

## Closure Gate 3 - Teardown design and destroy plans

Status: **COMPLETE**

Durable review:

- `docs/lifecycle/terraform-destroy-plan-review.md`.

Completed plan runs:

| Stage | Run ID | Source commit | Managed deletes | Result |
|---|---:|---|---:|---|
| `frontend-delivery` | `29856519775` | `36a62f8e…` | 14 | PASS |
| `rag-runtime` | `29856522168` | `36a62f8e…` | 23 | PASS |
| `eks-runtime` | `29856524234` | `36a62f8e…` | 30 | PASS |
| `stateful-dependencies` | `29856526566` | `36a62f8e…` | 5 | PASS |
| `runtime-dependencies` | `29856528584` | `36a62f8e…` | 16 | PASS |
| `network` | `29856530899` | `36a62f8e…` | 16 | PASS |
| `foundation` | `29858008935` | `7f6f32a4…` | 16 | PASS |
| **Total** | — | — | **120** | **PASS** |

Final conclusions:

- all 120 Terraform-managed resource instances are represented by delete-only actions;
- create, update, replacement and import counts are zero;
- all seven plans passed the destroy-only contract;
- the foundation state-bucket safeguard remains committed;
- the foundation plan used a runner-temporary override and recorded `foundation_override_committed=false`;
- all state-external cleanup prerequisites are assigned to runtime or bootstrap phases;
- no resource deletion occurred.

The reviewed plan artifacts cannot be applied later. An approved execution workflow must generate and apply a fresh saved plan in the same job after checking the exact stage contract.

## Closure Gate 4 - Approved runtime teardown

Status: **READY FOR FIRST STAGE APPROVAL — EXECUTION NOT STARTED**

Execution implementation and registration:

- staged runtime teardown workflow merged through PR #97;
- identical manual-dispatch workflow registered on the default branch through PR #98;
- GitHub OIDC bootstrap hardening merged through PR #99;
- foundation/bootstrap deletion remains excluded;
- one exact runtime stage is permitted per dispatch;
- global concurrency prevents simultaneous teardown stages;
- every stage requires exact source commit, AWS account, stage, reviewed maximum delete count and stage-specific destructive confirmation;
- a fresh saved destroy plan is generated, checked against the reviewed address allowlist and applied in the same job;
- state-aware subset recovery is permitted only after partial success;
- unreviewed addresses, creates, updates, replacements, imports and invalid data-source actions are rejected.

Execution environment readiness confirmed on 2026-07-22:

```text
environment=aws-live-teardown
deployment_branch=agent/rdb-domain-realignment
role_arn=arn:aws:iam::024863981627:role/terraformers-live-teardown
required_environment_variables=4
required_tfvars_secrets=6
missing_tfvars_secrets=0
setup_result=READY_WITHOUT_DISPATCH
```

The environment contains:

- `AWS_REGION`;
- `AWS_ROLE_TO_ASSUME`;
- `AWS_TERRAFORM_STATE_BUCKET`;
- `AWS_TERRAFORM_STATE_PREFIX`;
- all six non-foundation private tfvars Secrets required by the runtime stages.

The state-external `terraformers-live-teardown` role:

- trusts only `repo:siamese-lang/Terraformers-modernization:environment:aws-live-teardown`;
- has ReadOnlyAccess plus the project teardown inline policy;
- does not have AdministratorAccess;
- remains available until runtime residual verification is complete;
- cannot remove the final foundation credentials or itself.

Approved stage order remains:

1. `frontend-delivery` — reviewed maximum 14 deletes;
2. `kubernetes-owners` — 0 Terraform deletes;
3. `rag-runtime` — reviewed maximum 23 deletes;
4. `eks-runtime` — reviewed maximum 30 deletes;
5. `stateful-dependencies` — reviewed maximum 5 deletes;
6. `runtime-dependencies` — reviewed maximum 16 deletes;
7. `network` — reviewed maximum 16 deletes.

No runtime teardown workflow has been dispatched. No CloudFront, S3, Kubernetes, Argo CD, AOSS, EKS, RDS, Cognito, SQS, ECR, Secret, log, IAM, VPC or Terraform-managed resource has been deleted for portfolio closure.

The first destructive boundary is a separately approved `frontend-delivery` dispatch with:

```text
stage=frontend-delivery
reviewed_maximum_delete_count=14
confirmation=DESTROY_REVIEWED_FRONTEND_DELIVERY_14
```

A successful stage must complete its post-apply state and service residual checks. The next stage must not be dispatched automatically.

## Closure Gate 5 - Bootstrap teardown and zero-resource proof

Status: **NOT STARTED**

The state bucket, Terraform plan/apply roles, teardown role and GitHub OIDC provider remain required until runtime residual proof passes.

## Closure Gate 6 - Redeployment proof and repository closure

Status: **DOCUMENTED, NOT EXECUTED**

Completed:

- zero-state bootstrap and canonical redeployment order documented in `docs/lifecycle/aws-redeploy-runbook.md`;
- live owner and retention inventory reconciled with the teardown design;
- all seven Terraform destroy plans reconciled to the managed state inventory;
- staged runtime teardown workflow implemented, registered and prepared with its dedicated environment and role.

Remaining:

- execute each explicitly approved runtime teardown stage;
- record runtime and bootstrap residual results;
- execute separately approved bootstrap teardown;
- create the final repository release/tag after zero-resource proof.

## Current next action

Obtain explicit approval for the first `frontend-delivery` runtime teardown dispatch against the exact current integration commit. Do not dispatch it automatically, and do not proceed to `kubernetes-owners` unless the frontend stage and residual verification succeed.
