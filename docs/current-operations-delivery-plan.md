# Terraformers Current Operations and Delivery Plan

Status: controlling execution plan after PR A delivery evidence on 2026-07-21

## 1. Authority and conflict resolution

This document is the current execution source of truth for the remaining Terraformers modernization work.

It does not replace the fixed architecture and non-regression decisions in `docs/source-rag-gitops-reuse-plan.md`. It replaces only stale progress statements, old "immediate next work" sections, and phase ordering that still describe RAG as unfinished.

When repository documents conflict:

1. Preserve the project identity and fixed architecture decisions from `docs/source-rag-gitops-reuse-plan.md`.
2. Use this document for current completion state, execution order, implementation scope, and stop conditions.
3. Use live AWS, Kubernetes, workflow, browser, and runtime evidence over old plans or historical descriptions.
4. Do not reopen completed RAG work unless a later main-service workflow exposes one specific correctness defect.
5. Change this plan only when the user explicitly approves a scope or sequence change.

A new conversation must read this file before proposing work. It must inspect the current repository and live state once, then continue from the first incomplete gate instead of recreating a new roadmap.

## 2. Project identity and portfolio objective

Terraformers-modernization remains the operational modernization of the 2024 five-person Terraformers team project. It is not a new personal project and must not be presented as a solo 2024 implementation.

The remaining portfolio objective is to prove one coherent operating lifecycle:

> code change -> verification -> immutable image publication -> Git desired-state update -> ArgoCD reconciliation -> runtime and browser verification -> monitoring -> load and scaling -> bounded failure -> recovery or rollback -> restored state

The portfolio must demonstrate container-based AWS web-service delivery, cloud architecture, observability, autoscaling, failure diagnosis, recovery, and evidence-based operations. Adding more AI sophistication or frontend features is not a completion goal.

## 3. Completed baseline

The following are complete and must not be redesigned without a concrete defect:

- Spring Boot owns the analysis lifecycle.
- Cognito identity, RDB ownership and metadata, Flyway validation, and S3 object storage boundaries are established.
- EKS, ECR, RDS, S3, CloudFront, IAM/IRSA, managed Secrets, and the private Backend origin are the current AWS architecture.
- CloudFront remains the only public product entry.
- Backend images use immutable tags and digests.
- Private Bedrock embedding -> AOSS vector retrieval -> Bedrock Terraform draft generation has been proven live.
- Corpus v2 contains AWS Provider 5.100.0 schema and examples and passed one bounded v1/v2 comparison.
- RAG work is closed. Generated Terraform remains a reviewable draft rather than an automatically deployable artifact.
- Existing Backend image publication and Frontend S3/CloudFront delivery workflows are reusable foundations.

## 4. Fixed execution constraints

The following constraints remain binding:

- Reuse current repository workflows, Terraform roots, Kubernetes manifests, scripts, and older repositories before creating replacements.
- Do not restore the former Python analysis service.
- Do not add a direct public ALB, public AOSS, or public ArgoCD administration endpoint.
- Do not store static AWS credentials, GitHub PATs, kubeconfig, tfvars, tfstate, prompts, source images, embeddings, retrieved text, generated Terraform, or Secrets in repository evidence.
- GitHub Actions image publication must not run `kubectl apply`, `kubectl set image`, or equivalent direct deployment commands.
- Terraform apply remains separately approved and must not become an automatic merge-side action.
- Do not copy the 2024 Prometheus, Grafana, or X-Ray implementation verbatim. Reuse the operational intent only.
- Do not add a monitoring platform merely to show more tools. Every metric, trace, dashboard, and alarm must support a selected operating scenario.
- Do not generate a new verifier or recovery script for each failure. Diagnose the first actual failing boundary and reuse existing mechanisms.
- Do not split one meaningful implementation into many documentation, verifier, or micro-fix PRs unless an independently reviewable safety boundary requires it.
- Do not run high-volume Bedrock analysis load tests. Use a non-AI product/API path for autoscaling load and a small bounded set for AI latency and failure behavior.
- Do not claim high availability beyond the actual replica, node, AZ, database, and ingress design.

## 5. Current execution sequence

Work proceeds in the following order. Later phases must not pull work forward unless it is a prerequisite for the current phase.

### Gate 0 - Read-only operating baseline inventory

Purpose: determine the actual current state and exact implementation gaps before changing AWS, Kubernetes, workflows, or application code.

Inspect once:

- current integration branch and merged PR state
- Backend, Frontend, Terraform, Kubernetes, and existing deployment workflows
- canonical Backend AWS overlay and current image-digest handling
- ArgoCD installation, Application, repository, revision, sync, and health state
- EKS nodes, node groups, allocatable capacity, Pod requests/limits, and namespace workloads
- Backend Deployment, Service, endpoints, probes, rollout strategy, replicas, image, and image ID
- Metrics Server and CloudWatch Observability add-on state
- current logs, log groups, dashboards, alarms, and tracing configuration
- ALB/CloudFront health and public product path
- RDS backup/retention, S3 versioning, Terraform state, and corpus re-ingestion boundaries
- expected cost of the remaining implementation and whether a temporary second node is required

Deliverable: one concise inventory table with `current state`, `gap`, `required action`, `cost/risk`, and `evidence source`.

Stop condition: the exact scope of PR A is known. Gate 0 performs no cluster mutation, AWS apply, release, or new verification framework.

### PR A - Immutable-digest Backend GitOps delivery

Goal: make Git the Backend desired-state source and ArgoCD the release reconciler.

Required chain:

1. Backend change passes scoped CI.
2. Existing GitHub OIDC workflow builds and pushes an immutable ECR image.
3. The workflow resolves the digest.
4. A bounded branch or pull request updates the canonical environment overlay to the digest.
5. ArgoCD tracks the real repository, revision, and path.
6. ArgoCD becomes `Synced` and `Healthy`.
7. Git digest, Deployment image, and Pod runtime image ID match.
8. CloudFront browser smoke passes.
9. Git revert restores the previous digest and browser smoke passes again.
10. One safe non-secret drift is corrected by ArgoCD self-heal.

Frontend delivery stays separate: test/build on pull requests, then the existing GitHub OIDC S3 sync and CloudFront invalidation workflow for approved delivery.

Terraform stays separate: automatic static checks and plan preparation are allowed; apply remains manual and approved.

### PR B - Operations visibility

Default direction:

- CloudWatch Observability / OpenTelemetry for EKS infrastructure metrics and logs
- Micrometer Prometheus registry for internal Backend application metrics
- OpenTelemetry tracing exported to X-Ray-compatible AWS tracing
- CloudWatch dashboards and a small number of actionable alarms
- Grafana only if a concrete visualization gap remains after the AWS-native baseline

Minimum application signals:

- HTTP request count, latency, and 5xx
- AnalysisJob started, succeeded, failed, and elapsed time
- Bedrock invocation latency and failures
- AOSS retrieval latency, failures, and hit count
- executor queue and rejection state where useful
- database connection-pool pressure
- safe correlation by analysis job ID, trace ID, deployment revision, and image digest

No user ID, project ID, prompt, document text, generated Terraform, or other high-cardinality or sensitive values may be metric labels or trace attributes.

Completion evidence: one real analysis can be followed from browser request through safe log correlation, metrics, trace, and deployment revision.

### PR C - Availability and autoscaling

Goal: verify controlled scale-out, traffic continuity, and scale-in with the minimum meaningful Kubernetes changes.

Review and implement only as capacity permits:

- Backend replicas
- RollingUpdate `maxUnavailable` and `maxSurge`
- HPA using available resource metrics
- Metrics Server if absent
- PodDisruptionBudget where meaningful
- topology spread or anti-affinity where the actual node/AZ design can support it
- requests and limits based on observed baseline rather than arbitrary values

Load-test rules:

- use JMeter against a non-Bedrock product/API path through the actual public path
- record baseline, sustained load, scale-out, new Pod readiness, target health, success rate, latency, load removal, and scale-in
- use only a small bounded AI analysis sample for Bedrock/AOSS stage latency
- temporary node-group scale-up is allowed only when separately approved and must be followed by a retention or scale-down decision

Completion evidence: the workload scales, serves traffic within the recorded acceptance boundary, and scales down without claiming more availability than was actually tested.

### PR D - Failure, recovery, and closure

Primary operating scenarios:

1. Backend Pod failure under low sustained traffic
   - observe first failing boundary, readiness and target health, user-visible effect, replacement Pod, and restored service
2. GitOps release rollback
   - release a safe identifiable change, verify the new digest, revert the manifest commit, verify the old digest and browser path return

Recovery boundaries to document and test where practical:

- RDS backup, schema, and restore assumptions
- S3 source/result version or restore behavior
- AOSS corpus source, version, checksum, and repeatable re-ingestion
- Terraform remote-state and lock recovery assumptions
- Git desired state and rollback history

Final closure includes sanitized evidence, operations runbook, architecture update, portfolio summary, interview explanation, PR #32 update, integration merge, release tag, and explicit AWS retention/scale-down/deletion decisions.

## 6. CI/CD responsibility split

| Area | Pull request verification | Approved delivery |
|---|---|---|
| Backend | Maven tests/package, container build, runtime contract checks | ECR immutable image -> digest update PR -> ArgoCD reconcile |
| Frontend | npm test and production build | existing OIDC S3 sync -> CloudFront invalidation |
| Terraform/infrastructure | fmt, validate, static checks, reviewed plan | separate manual approved apply |
| Kubernetes/GitOps | Kustomize render, schema and digest contract | Git merge followed by ArgoCD |
| Documentation | minimum link/path consistency | no runtime mutation |

Path filters should prevent unrelated areas from running expensive or irrelevant workflows. Separate responsibility does not mean separate repositories or rebuilding current workflows.

## 7. Evidence and acceptance discipline

For each live scenario, record only:

- source commit and workflow run
- ECR digest
- manifest-update or revert commit
- ArgoCD revision, sync, and health
- Deployment generation, Pod name, node, and image ID
- browser/API outcome
- metric, alarm, trace, and sanitized log identifiers
- elapsed time and recovery outcome
- cost and retention decision

Every scenario must state:

1. healthy baseline
2. introduced change or bounded failure
3. first failing boundary
4. user-visible effect
5. detection evidence
6. recovery action
7. restored runtime, data, digest, and browser state

A successful command or source merge alone is not completion evidence.

## 8. New-conversation handoff contract

Use the following instruction when work moves to another conversation:

> Continue `siamese-lang/Terraformers-modernization` from `docs/current-operations-delivery-plan.md`. Treat that file as the current execution source of truth and preserve the fixed architecture decisions in `docs/source-rag-gitops-reuse-plan.md`. RAG v2 and PR #73 are complete; do not add more RAG work without one concrete main-service defect. Inspect the current repository and live state once, resume from the first incomplete gate, and do not redesign the roadmap. Reuse existing workflows, manifests, Terraform roots, and scripts. Avoid micro-PRs, verifier expansion, repeated preflights, and new scripts unless an actual repeated operating need justifies them. Do not mutate AWS, Kubernetes, Terraform, ArgoCD, deployments, or merge a PR without explicit approval. The current sequence is Gate 0 inventory -> PR A GitOps delivery -> PR B operations visibility -> PR C autoscaling/availability -> PR D failure/recovery/closure.

## 9. Current next action

PR A is complete. Sanitized delivery evidence: GitOps revision `da7cdc3ae98a36b305020daf635690f53305687a`; Argo CD core components were Running; the Backend Application was Synced and Healthy; Git desired digest, Deployment image, and Pod image ID matched `sha256:9e8ebd25c3afcc18cd03cb62c97bfc4200ff63477329ad548c8c4a31a518a254`; the CloudFront login-to-Terraform-view flow passed; and Argo CD self-heal restored a manual Backend replica drift from 2 to 1.

PR B, Operations visibility, is now active. Two worker nodes are deliberately retained because one worker exhausted Pod capacity during Argo CD installation. Do not repeat PR A render, release, browser, self-heal, or digest-parity tests; proceed with the source-controlled AWS-native observability package only.