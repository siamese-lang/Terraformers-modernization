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

Status: **IN PROGRESS — SIX PLANS REVIEWED, FOUNDATION REPLAN REQUIRED**

Durable review:

- `docs/lifecycle/terraform-destroy-plan-review.md`.

Completed plan runs from source commit `36a62f8e0368ce22d19a54cca526fdfb85abffd9`:

| Stage | Run ID | Managed deletes | Result |
|---|---:|---:|---|
| `frontend-delivery` | `29856519775` | 14 | PASS |
| `rag-runtime` | `29856522168` | 23 | PASS |
| `eks-runtime` | `29856524234` | 30 | PASS |
| `stateful-dependencies` | `29856526566` | 5 | PASS |
| `runtime-dependencies` | `29856528584` | 16 | PASS |
| `network` | `29856530899` | 16 | PASS |
| `foundation` | `29856533560` | not generated | blocked by committed state-bucket `prevent_destroy` safeguard |

Six successful plans account for 104 managed deletes. They contain no create, update, replacement or import action and passed the delete-only contract.

The foundation failure is not an IAM, state, tfvars, provider, or account failure. Terraform intentionally rejects the plan because the state bucket retains `lifecycle.prevent_destroy = true`.

Approved correction scope for planning only:

1. keep `prevent_destroy = true` in committed foundation source;
2. create `zz-foundation-destroy-plan_override.tf` only in the GitHub-hosted runner checkout;
3. set `prevent_destroy = false` only for `destroy_stage=foundation`;
4. record and remove the temporary override before artifact upload;
5. rerun only the foundation plan from the new exact integration commit;
6. do not apply any plan.

Gate 3 stop condition:

- the foundation plan shows the expected remaining 16 managed deletes;
- all seven plans are delete-only;
- all 120 Terraform-managed resources reconcile to the inventory;
- non-state cleanup prerequisites remain assigned to the correct execution phase;
- bootstrap remains the final teardown phase.

## Closure Gate 4 - Approved runtime teardown

Status: **NOT STARTED**

No project resource has been deleted for portfolio closure.

Runtime deletion requires explicit approval after Closure Gate 3 completes.

## Closure Gate 5 - Bootstrap teardown and zero-resource proof

Status: **NOT STARTED**

The state bucket, Terraform plan/apply roles, and GitHub OIDC provider remain required until runtime residual proof passes.

## Closure Gate 6 - Redeployment proof and repository closure

Status: **DOCUMENTED, NOT EXECUTED**

Completed:

- zero-state bootstrap and canonical redeployment order documented in `docs/lifecycle/aws-redeploy-runbook.md`;
- live owner and retention inventory reconciled with the teardown design.

Remaining:

- complete the foundation destroy-plan review;
- execute approved teardown;
- record runtime and bootstrap residual results;
- create the final repository release/tag after zero-resource proof.

## Current next action

Validate and merge the runner-temporary foundation destroy-plan override. Register the corrected workflow on the default branch, then rerun only the foundation plan. Do not execute any deletion.