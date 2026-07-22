# Terraformers Portfolio Closure and Lifecycle Plan

Status: runtime teardown completed after PR #106; read-only runtime closure verification is the next gate

## 1. Authority and conflict resolution

This document is the current execution source of truth for the remaining Terraformers modernization work.

It preserves the project identity and reuse decisions in `docs/source-rag-gitops-reuse-plan.md`. Use `docs/project-system-overview.md` for the final architecture and `docs/lifecycle/aws-runtime-teardown-closure.md` for the completed runtime teardown record.

When repository documents conflict:

1. Preserve the project as the modernization of the 2024 five-person Terraformers team project.
2. Preserve the reuse-first decisions from the original repository and `siamese-lang/rdb-refactor`.
3. Use this document for the current completion state, execution order, stop conditions, and approval boundaries.
4. Use live AWS, Terraform state, workflow, browser, and runtime evidence over historical plans.
5. Do not reopen RAG, autoscaling, monitoring-stack expansion, frontend redesign, or new application features without one concrete defect that blocks closure.
6. Do not create another broad verifier, recovery framework, or micro-PR sequence for already completed runtime deletion.

A new conversation must read this file first, then `docs/project-system-overview.md` and `docs/lifecycle/aws-runtime-teardown-closure.md`. It must resume from the first incomplete gate rather than create a new roadmap.

## 2. Project identity and interview objective

Terraformers-modernization remains the operational modernization of the 2024 Terraformers team project. It is not a new solo project and must not be presented as a solo 2024 implementation.

The portfolio title remains:

> Terraformers: Backend and Cloud Infrastructure Modernization

The project must support a concrete explanation of:

- how the original team project and first RDB refactor were reused rather than rebuilt;
- how Backend, RDB, S3, Cognito, Bedrock, AOSS, EKS, CloudFront, IAM, and Secrets boundaries were aligned;
- how immutable image delivery, Git desired state, Argo CD reconciliation, and browser verification were connected;
- how live failures were isolated at the first failing boundary;
- how AWS-native telemetry was bounded to the project goal;
- how the runtime environment was inventoried and removed without relying on the local Windows machine for Terraform execution;
- what remained outside runtime closure and why it requires a separate approval.

The final portfolio must distinguish implemented source, proven live behavior, documented procedures, and deliberate non-claims.

## 3. Completed baseline that must not be redesigned

The following are complete and must not be reopened without a closure-blocking defect:

- Spring Boot owns the analysis lifecycle.
- Cognito identity, RDB ownership and metadata, Flyway validation, and S3 object responsibilities are separated.
- The deployed architecture used EKS, ECR, RDS, S3, SQS, Cognito, IAM/IRSA, Secrets Manager, CloudFront, Bedrock, and AOSS.
- CloudFront was the only public product entry.
- Backend delivery used immutable ECR digests and GitOps reconciliation.
- Private Bedrock embedding -> AOSS retrieval -> Bedrock Terraform generation was proven live.
- Corpus v2 and the bounded RAG comparison are closed.
- AWS-native operations visibility source and live evidence are closed to the extent recorded in the final evidence guide.
- Runtime teardown source, recovery, and evidence were completed through PR #106.
- All six runtime Terraform states reached zero managed instances.
- The exact runtime VPC was deleted after its final non-default security-group dependency was removed.

Do not claim autoscaling, multi-replica application HA, multi-region DR, generated-code deployment, or a completed RDS restore drill.

## 4. Binding execution constraints

- Reuse current workflows, Terraform roots, manifests, scripts, and documents before creating replacements.
- Do not restore the former Python analysis service.
- Do not add public ALB, public AOSS, public Argo CD, or a second monitoring stack.
- Do not store AWS credentials, GitHub PATs, kubeconfig, tfvars, raw tfstate, saved plans, prompts, retrieved text, generated Terraform, or Secret values in evidence.
- Terraform mutation remains separately approved.
- Do not rerun a destructive workflow solely to turn a completed deletion into a green GitHub status.
- Do not treat Terraform state zero as sufficient proof without exact residual verification.
- Do not use account-wide fuzzy name/tag scans where an exact resource identity or exact canonical name is available.
- The local Windows machine is not the canonical Terraform execution environment.
- Foundation, state-bucket, and OIDC deletion require a new explicit approval after a separate bounded review.

## 5. Closure gates and current status

### Gate 1 - Read-only inventory

Status: complete.

The seven Terraform states, Kubernetes owners, controller-generated resources, mutable service data, and bootstrap boundary were classified in the lifecycle inventory.

### Gate 2 - Evidence freeze and interview record

Status: complete for runtime closure.

The final evidence and interview guide records implemented, proven, documented, and non-claimed areas. No additional live service work is required merely to improve presentation.

### Gate 3 - Runtime teardown design and destroy-plan review

Status: complete.

The approved runtime order was:

1. `frontend-delivery`;
2. Kubernetes/controller owners;
3. `rag-runtime`;
4. `eks-runtime`;
5. `stateful-dependencies`;
6. `runtime-dependencies`;
7. `network`.

Bootstrap/state/OIDC remained excluded.

### Gate 4 - Approved runtime teardown

Status: complete.

The destructive work completed even though several runs ended with residual-check false negatives after state zero or exact resource deletion. The authoritative incident and completion record is `docs/lifecycle/aws-runtime-teardown-closure.md`.

The old destructive workflow must not be rerun merely to obtain a successful conclusion.

### Gate 5 - Read-only runtime closure verification

Status: pending.

Run `.github/workflows/aws-runtime-closure-verification.yml` once after the closure PR is merged.

The workflow must:

- verify all six runtime state counts are zero;
- verify the Kubernetes owner-removal marker;
- check exact runtime AWS names or identities;
- classify an active Secret separately from a Secret already pending deletion;
- produce only sanitized counts;
- leave foundation unchecked and undeleted.

Stop condition: the workflow reports no active runtime resource and records any AWS pending-deletion tombstone separately.

### Gate 6 - Bootstrap/state/OIDC decision

Status: not approved and not started.

Before any mutation, present one bounded inventory containing:

- state bucket versions and lock objects;
- GitHub OIDC provider ownership and whether it is project-specific;
- foundation, plan, apply, delivery, and teardown IAM roles/policies still present;
- the independent identity required to remove the final OIDC/state resources;
- GitHub Environment, variable, and secret retention decisions;
- the redeployment consequence of deleting or retaining each item.

A new explicit user approval is mandatory. Runtime teardown approval does not extend to this gate.

### Gate 7 - Repository closure

Status: pending after the bootstrap decision.

Repository closure includes:

- final closure verification evidence;
- aligned lifecycle documents;
- final evidence/interview guide;
- a decision on whether bootstrap is retained for future redeployment or deleted for zero-AWS-resource proof;
- a final integration merge and optional release tag.

Actual redeployment is not required unless the user explicitly opens a new AWS deployment window.

## 6. Runtime teardown findings retained as engineering evidence

The teardown identified three process defects:

1. state-zero prerequisites did not prove asynchronous or non-Terraform residual convergence;
2. broad account-wide scans produced false-negative workflow conclusions;
3. long provider deletion timeouts hid the exact VPC dependency.

The corrected rule is:

> Resolve the exact state-owned resource, inventory external dependencies before a long delete, apply one bounded correction only when the inventory proves it is needed, and verify the exact identity afterward.

These incidents are retained for interview explanation. They are not a reason to reopen the architecture or add more validation layers.

## 7. Current next action

1. Merge the PR containing the read-only closure workflow, idempotent network recovery, and runtime teardown closure document after checks pass.
2. Run `AWS Runtime Closure Verification` once against the merged integration commit.
3. Record the sanitized result.
4. Present the bootstrap/state/OIDC inventory and decision boundary separately.
5. Do not mutate bootstrap resources without a new explicit approval.

No further runtime destroy execution is planned.

## 8. New-conversation handoff contract

> Continue `siamese-lang/Terraformers-modernization` from `docs/current-operations-delivery-plan.md`, then read `docs/project-system-overview.md` and `docs/lifecycle/aws-runtime-teardown-closure.md`. Runtime deletion through the network state is complete after PR #106. Do not rerun the destructive runtime workflow merely to obtain green status. The next gate is one read-only runtime closure verification. After that, inspect and present the bootstrap/state-bucket/GitHub-OIDC boundary separately and require explicit approval before mutation. Preserve the project as the modernization of the 2024 five-person Terraformers team project, preserve reuse-first decisions, and do not reopen RAG, autoscaling, monitoring expansion, frontend redesign, or new application features without a concrete closure-blocking defect.
