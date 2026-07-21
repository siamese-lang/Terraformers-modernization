# Portfolio Closure Progress

This file records the current completion point for `docs/current-operations-delivery-plan.md`. A new conversation should read this file after the controlling plan and `docs/project-system-overview.md`, then resume from the first incomplete item below.

Last updated from integration source commit:

```text
c5ed6f98a325a469ba9b29f6dec6f6c030b5f4ab
```

## Closure Gate 1 - Read-only live inventory

Status: **IN PROGRESS — TERRAFORM AND KUBERNETES OWNER INVENTORIES COMPLETE**

Completed:

- all seven expected remote Terraform state objects were read successfully;
- exact source commit and AWS account were verified;
- Terraform version, state serial, sanitized addresses, and type counts were recorded;
- 153 total state instances were found: 120 managed resources and 33 data sources;
- no raw state, outputs, tfvars, saved plan, or Secret value was retained;
- no Terraform plan/apply/destroy or AWS mutation occurred;
- durable Terraform result: `docs/lifecycle/aws-terraform-state-inventory-result.md`;
- Argo CD Backend Application was verified `Synced/Healthy` at the current integration revision;
- desired Backend image and running Pod image ID matched the same immutable ECR digest;
- Backend Pod was Ready with zero restarts;
- the runtime namespace contained one Deployment, one Service, and one Ingress;
- External Secrets Operator and AWS Load Balancer Controller were each Ready `1/1`;
- one ExternalSecret and one SecretStore were present without inspecting Secret contents;
- one internal ALB with one target group and one healthy target was confirmed;
- durable Kubernetes/ALB result: `docs/lifecycle/kubernetes-and-alb-inventory-result.md`.

Important findings:

- the GitHub OIDC provider is not represented in `bootstrap` state and its ownership must be resolved before deletion;
- the internal ALB is referenced by `frontend-delivery` but is owned by the Kubernetes Ingress and AWS Load Balancer Controller;
- the ALB scheme is `internal`, and no public Backend ALB was observed;
- the correct ALB teardown path is CloudFront VPC-origin removal -> Ingress deletion -> controller reconciliation -> ALB dependency residual check;
- ECR images, S3 versions, Secret values, RDS snapshots/managed credential Secret, Cognito users, AOSS index/documents, CloudWatch logs, and X-Ray traces are outside state;
- EKS must not be destroyed before Argo CD, Ingress, operators, and controller-generated load-balancer resources are removed;
- the earlier blank `argocd_controller=` value came from querying Deployments only; the non-HA Application Controller is expected to be a StatefulSet and must be counted in the final owner pass.

Remaining:

1. one bounded AWS read-only inventory for data-only and service-generated resources;
2. final Kubernetes owner counts for Argo CD StatefulSet/Helm release, ServiceAccounts, generated Secret existence, temporary Jobs/Pods, and namespaces;
3. exact ALB listener/rule, generated security-group, and load-balancer ENI counts for residual checks;
4. GitHub Environment/variable/secret-name inventory and GitHub OIDC provider ownership classification;
5. retention decisions for RDS snapshots, S3 versions, ECR images, Secrets deletion mode, AOSS data, and CloudWatch logs;
6. update `docs/lifecycle/aws-resource-inventory.md` from `PENDING_LIVE_INVENTORY` to confirmed live values.

Stop condition not yet met.

## Closure Gate 2 - Evidence freeze and interview record

Status: **IN PROGRESS — RUNTIME PARITY REFRESHED**

Completed:

- complete system overview;
- expanded interview guide with seven representative difficulties;
- teardown and redeployment boundary documentation;
- immutable Backend image digest recorded;
- actual browser analysis, Application Signals, X-Ray, and custom metric results frozen in `docs/portfolio/last-verified-live-evidence.md`;
- current Argo CD revision refreshed to `c5ed6f98a325a469ba9b29f6dec6f6c030b5f4ab`;
- current desired image and Pod runtime image parity verified;
- Backend readiness and zero restart state verified.

Remaining:

- designate the already verified successful browser analysis as the final bounded analysis result or run one final browser check only if current state contradicts it;
- freeze any sanitized architecture or UI screenshots required for the portfolio;
- complete remaining `PENDING_FINAL_EVIDENCE` fields without copying raw logs or sensitive data;
- perform one final minimal parity refresh immediately before teardown only if more source changes merge.

Stop condition not yet met.

## Closure Gate 3 - Teardown design and destroy plans

Status: **NOT STARTED**

Do not start until Closure Gate 1 inventory and retention decisions are complete.

No destroy-plan workflow exists yet. This is intentional.

## Closure Gate 4 - Approved runtime teardown

Status: **NOT STARTED**

No runtime resource has been deleted for portfolio closure.

## Closure Gate 5 - Bootstrap teardown and zero-resource proof

Status: **NOT STARTED**

The state bucket, Terraform roles, and OIDC/bootstrap boundary remain required.

## Closure Gate 6 - Redeployment proof and repository closure

Status: **DOCUMENTED, NOT EXECUTED**

Completed:

- `docs/lifecycle/aws-redeploy-runbook.md` describes zero-state bootstrap and canonical redeployment order.

Remaining:

- reconcile the runbook with the completed live inventory;
- record final teardown results;
- create final release/tag after zero-resource proof.

## Current next action

Perform one compact, read-only data and residual-owner inventory. Output must be counts and status only, not raw policies, object lists, Secret values, log dumps, or trace payloads. Use it to complete Closure Gate 1 and make retention decisions.

Do not create destroy automation, run Terraform destroy, delete Kubernetes owners, disable CloudFront, or alter GitHub OIDC until the remaining inventory and retention decisions are recorded.