# Terraformers Portfolio Closure and Lifecycle Plan

Status: controlling execution plan after the source changes through PR #86 on 2026-07-21

## 1. Authority and conflict resolution

This document is the current execution source of truth for the remaining Terraformers modernization work.

It preserves the project identity and fixed architecture decisions in `docs/source-rag-gitops-reuse-plan.md`, but it replaces the former Gate 0 / PR A-D progress sequence and every stale statement that says Operations Visibility, autoscaling, or RAG expansion is the immediate next task.

When repository documents conflict:

1. Preserve the project identity and reuse decisions from `docs/source-rag-gitops-reuse-plan.md`.
2. Use this document for the current completion state, execution order, stop conditions, teardown boundary, and redeployment boundary.
3. Use live AWS, Kubernetes, workflow, browser, and runtime evidence over historical plans.
4. Do not reopen RAG, autoscaling, monitoring-stack expansion, frontend redesign, or new service work without one concrete defect that blocks closure.
5. Do not change this plan unless the user explicitly changes the closure scope.

A new conversation must read this file first, inspect the current repository and live state once, and resume from the first incomplete closure gate. It must not create a new roadmap.

## 2. Project identity and interview objective

Terraformers-modernization remains the operational modernization of the 2024 five-person Terraformers team project. It is not a new personal project and must not be presented as a solo 2024 implementation.

The portfolio title remains:

> Terraformers: Backend and Cloud Infrastructure Modernization

The project must support a concrete interview explanation of:

- how the original team project and the first RDB refactor were reused instead of rebuilt;
- how Backend, RDB, S3, Cognito, SQS, Bedrock, AOSS, EKS, CloudFront, IAM, and Secrets boundaries were aligned;
- how immutable image delivery, Git desired state, Argo CD reconciliation, and browser verification were connected;
- how live AWS failures were diagnosed from the first failing boundary instead of hidden behind repeated validation scripts;
- how telemetry, logs, traces, and deployment revision were designed for bounded correlation;
- how the environment can be inventoried, removed, and later rebuilt without depending on the local Windows machine for Terraform execution.

The final portfolio must distinguish facts that were implemented, facts that were proven live, facts that are only documented, and areas deliberately left out.

## 3. Completed baseline that must not be redesigned

The following are complete source or live baselines and must not be redesigned without a closure-blocking defect:

- Spring Boot owns the analysis lifecycle.
- Cognito identity, RDB ownership and metadata, Flyway validation, and S3 object storage responsibilities are separated.
- EKS, ECR, RDS, S3, SQS, Cognito, IAM/IRSA, Secrets Manager, CloudFront, Bedrock, and AOSS are the current AWS architecture.
- CloudFront remains the only public product entry.
- Backend images use immutable tags and ECR digests.
- Git contains the Backend desired image digest and Argo CD reconciles the Backend application.
- Private Bedrock embedding -> AOSS vector retrieval -> Bedrock Terraform draft generation has been proven live.
- Corpus v2 contains curated AWS Provider 5.100.0 schema and examples and completed one bounded v1/v2 comparison.
- RAG is subordinate and closed. Generated Terraform remains a reviewable draft, not an automatically deployable result.
- AWS-native Operations Visibility source changes were merged through PR #86, including the CloudWatch add-on configuration, Application Signals workload selection, Micrometer metrics, safe log correlation, and the Pod-level non-root UID required by Java auto-instrumentation.

The final live observability result must be recorded from evidence. Source merge alone is not proof that Application Signals, X-Ray, or the final injected Pod state succeeded.

## 4. Binding execution constraints

- Reuse current workflows, Terraform roots, Kubernetes manifests, scripts, and prior repositories before creating replacements.
- Do not restore the former Python analysis service.
- Do not add a public ALB, public AOSS endpoint, public Argo CD endpoint, or second monitoring stack.
- Do not store static AWS credentials, GitHub PATs, kubeconfig, tfvars, tfstate, source images, prompts, embeddings, retrieved text, generated Terraform, account-specific values, or Secrets in repository evidence.
- GitHub Actions image publication must not deploy directly with `kubectl`.
- Terraform apply and destroy remain separately approved operations.
- Do not create one verifier, recovery contract, or shell script for every individual failure.
- Do not repeat a completed browser, GitOps, RAG, or telemetry verification unless the final evidence is missing or the current runtime contradicts it.
- Do not implement autoscaling or high availability merely because it appeared in an older plan. Do not claim it was completed.
- The local Windows machine is not the canonical Terraform execution environment. Use GitHub-hosted runners for normal plan/apply/destroy and AWS CloudShell only for the minimal bootstrap that cannot depend on the project OIDC role.
- No AWS or Kubernetes mutation is allowed during documentation and inventory-source preparation.

## 5. Closure execution sequence

Work proceeds in this order. Later gates must not be pulled forward.

### Closure Gate 1 - Read-only live inventory

Purpose: identify every current AWS, Terraform, Kubernetes, GitOps, generated, and manually initialized resource before planning deletion.

Required outputs:

- sanitized Terraform state address inventory for all seven state components;
- Kubernetes and Argo CD resource inventory;
- generated AWS resource inventory, including the internal ALB and target groups created by the AWS Load Balancer Controller;
- non-Terraform data inventory for ECR images, versioned S3 objects, AOSS indexes/documents, Cognito users, Secrets values, and CloudWatch logs;
- a classification of each item as Terraform-managed, GitOps/Kubernetes-managed, controller-generated, data-only, bootstrap, or external configuration;
- a delete owner, prerequisite, recreation source, retention decision, and residual check for each item.

The repository workflow `.github/workflows/aws-terraform-state-inventory.yml` supplies only sanitized Terraform state addresses and counts. It must never upload raw state or outputs. Live Kubernetes and AWS-generated resources are added from one bounded read-only operator pass.

Stop condition: `docs/lifecycle/aws-resource-inventory.md` contains no unexplained resource group and every deletion prerequisite has an owner.

### Closure Gate 2 - Evidence freeze and interview record

Purpose: preserve the project outcome and the engineering reasoning before AWS resources disappear.

Required outputs:

- final integration commit and immutable Backend image digest;
- Argo CD revision, sync, health, and runtime image parity;
- one final browser analysis outcome or the last valid bounded result;
- final observability state, explicitly distinguishing successful live signals from source-only preparation;
- architecture and delivery evidence that contains no secrets;
- a structured incident record using `symptom -> initial assumption -> evidence -> root cause -> bounded fix -> validation -> prevention -> interview follow-up`;
- explicit non-claims for autoscaling, multi-AZ application availability, automatic Terraform apply, and generated-code deployability.

The controlling interview artifact is `docs/portfolio/final-evidence-and-interview-guide.md`.

Stop condition: the project can be explained for 90 seconds, five minutes, and a technical deep dive without relying on memory or console access.

### Closure Gate 3 - Teardown design and destroy plans

Purpose: prove that the environment can be removed in dependency order before any resource is deleted.

Required outputs:

- approved retention decisions for RDS snapshots, S3 object versions, AOSS corpus data, Secrets deletion mode, CloudWatch log retention, and ECR images;
- a reverse-dependency teardown order covering GitOps, Kubernetes controllers, CloudFront, controller-generated load balancers, RAG, EKS, stateful dependencies, runtime dependencies, network, and bootstrap;
- one destroy plan per Terraform state component;
- explicit cleanup steps for resources and data not represented in Terraform state;
- a two-phase boundary: runtime teardown first, bootstrap/state/OIDC teardown last.

No destroy applies occur in this gate.

Stop condition: each destroy plan is reviewed, no unexplained replacement/create action exists, and the bootstrap role remains able to finish the teardown.

### Closure Gate 4 - Approved runtime teardown

Purpose: remove all project runtime resources while preserving the minimum bootstrap plane required to complete and verify deletion.

Execution order is controlled by `docs/lifecycle/aws-teardown-runbook.md`.

The operator must:

1. stop delivery and Argo CD reconciliation;
2. remove application and controller-owned resources before the EKS cluster;
3. destroy frontend, RAG, EKS, stateful, runtime, and network states in reviewed dependency order;
4. clean versioned buckets, ECR images, scheduled Secrets, logs, and other non-state data according to the approved retention decisions;
5. run a residual scan before touching bootstrap resources.

Stop condition: no project runtime resource remains and only the documented bootstrap plane is present.

### Closure Gate 5 - Bootstrap teardown and zero-resource proof

Purpose: remove the Terraform state bucket, project OIDC/foundation roles, and the final teardown identity only after every other project resource is gone.

Required proof:

- all runtime state components are empty or removed;
- the versioned state bucket is exported only if explicitly retained, then all object versions and delete markers are removed;
- project OIDC and foundation roles are removed in an order that does not strand the teardown;
- the final AWS residual scan reports no project resource;
- GitHub repository variables and secrets are either retained for future redeployment or deliberately removed as a separate non-AWS decision.

Stop condition: the AWS account contains no resource attributable to Terraformers-modernization under the approved project inventory.

### Closure Gate 6 - Redeployment proof document and repository closure

Purpose: ensure a future redeployment does not depend on forgotten console actions or the current local disk.

`docs/lifecycle/aws-redeploy-runbook.md` must cover:

- minimal AWS CloudShell bootstrap for the state bucket, GitHub OIDC provider, and foundation roles;
- GitHub Environment, variable, and secret names without recording values;
- the canonical Terraform stage order;
- External Secrets, AWS Load Balancer Controller, Argo CD, and Backend GitOps bootstrap;
- immutable image publication, frontend delivery, RAG corpus ingestion, Cognito test-user setup, and final browser/observability verification;
- rollback and restart points after a failed stage.

Repository closure then includes the final evidence document, lifecycle runbooks, an integration merge, and a release tag. Actual redeployment is not required after the final full teardown unless the user explicitly chooses to prove it with a new AWS deployment window.

## 6. Lifecycle management boundaries

| Boundary | Canonical owner | Examples |
|---|---|---|
| Terraform-managed AWS | Remote state component | VPC, EKS, RDS, IAM, S3 buckets, SQS, Cognito, CloudFront, AOSS collection |
| GitOps/Kubernetes | Git manifest and Argo CD or operator | Backend Deployment/Service/ConfigMap, Ingress, ExternalSecret |
| Controller-generated AWS | Kubernetes owner object | Internal ALB, target groups, generated security-group rules |
| Data and mutable contents | Service API or bounded cleanup step | ECR images, S3 versions, AOSS documents/index, Cognito users, Secret values, logs |
| Bootstrap | CloudShell first, GitHub Actions afterward | state bucket, OIDC provider, plan/apply roles |
| External configuration | GitHub repository/environment | variables, encrypted secrets, environment approvals |

Terraform state is necessary but not sufficient for complete teardown or redeployment.

## 7. Evidence discipline

Every retained live result must state:

1. source commit and workflow run;
2. immutable image digest where applicable;
3. desired-state revision and runtime image parity;
4. healthy baseline;
5. change or failure;
6. first failing boundary;
7. user-visible effect;
8. evidence used to isolate the cause;
9. bounded recovery action;
10. restored state and remaining limitation.

A command that returned success, a merged pull request, or an AWS resource that exists is not sufficient evidence by itself.

## 8. New-conversation handoff contract

Use the following instruction when work moves to another conversation:

> Continue `siamese-lang/Terraformers-modernization` from `docs/current-operations-delivery-plan.md`. This file is the controlling closure plan after PR #86. Preserve the project as the modernization of the 2024 five-person Terraformers team project and preserve the reuse decisions in `docs/source-rag-gitops-reuse-plan.md`. Do not reopen RAG, autoscaling, monitoring-stack expansion, frontend redesign, or new application features unless one concrete defect blocks closure. Inspect repository and live state once, then resume from the first incomplete Closure Gate. The sequence is read-only inventory -> evidence and interview record -> destroy-plan review -> explicitly approved runtime teardown -> residual scan -> explicitly approved bootstrap teardown -> zero-resource proof -> repository closure. Reuse existing workflows, Terraform roots, manifests, and scripts. Avoid micro-PRs, repeated preflights, one-script-per-failure behavior, and raw evidence dumps. Do not mutate AWS, Kubernetes, Terraform, Argo CD, deployments, or merge a PR without explicit approval.

## 9. Current next action

Create and review one non-mutating closure PR containing:

- this updated controlling plan;
- `docs/lifecycle/aws-resource-inventory.md`;
- `docs/lifecycle/aws-teardown-runbook.md`;
- `docs/lifecycle/aws-redeploy-runbook.md`;
- `docs/portfolio/final-evidence-and-interview-guide.md`;
- `.github/workflows/aws-terraform-state-inventory.yml`.

After that PR is merged, run the read-only Terraform state inventory once and complete Closure Gate 1. Do not design or run an approved destroy workflow until the inventory and retention decisions are complete.