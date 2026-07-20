# Terraformers Modernization Completion Plan

## 1. Purpose and project identity

Terraformers-modernization is the operational modernization of the 2024 AWS Cloud School five-person Terraformers team project. It is not a new personal project, a replacement product, or a separate demonstration service.

The portfolio focus remains:

- Spring Boot Backend API, domain, and persistence
- RDB and Flyway schema management
- S3 object content and RDB metadata responsibility separation
- Cognito authentication and user mapping
- Bedrock and OpenSearch vector RAG
- EKS, ECR, RDS, S3, CloudFront, IAM, and Secrets
- Terraform-managed AWS infrastructure
- GitHub Actions and ArgoCD immutable-digest GitOps
- browser E2E, observability, failure diagnosis, traffic continuity, rollback, and recovery
- runbooks and sanitized evidence

AI-generated Terraform sophistication and frontend feature expansion are not the center of the project. Existing user functionality is frozen unless an operational defect prevents final verification.

## 2. Overall completion gates

The project is complete only when all of the following groups are satisfied.

### 2.1 RAG and product path

1. Spring Boot owns the analysis job lifecycle.
2. Bedrock analyzes the uploaded architecture image.
3. The Backend creates a Bedrock embedding for retrieval.
4. OpenSearch Serverless performs vector k-NN retrieval against a project-owned corpus.
5. Retrieved documents are supplied to the Terraform generation context.
6. The result is stored and viewed through the existing authenticated product flow.

### 2.2 Immutable-digest GitOps

1. GitHub Actions builds and publishes the Backend image to ECR.
2. The immutable digest is recorded in Git-managed Kubernetes manifests.
3. ArgoCD tracks the actual repository and manifest path.
4. ArgoCD reaches `Synced` and `Healthy`.
5. Git, Deployment, and Pod runtime digests match.
6. Browser smoke, Git-revert rollback, and ArgoCD self-heal are demonstrated.

### 2.3 Operations and closure

1. Monitoring, alarms, probes, availability controls, and controlled-failure scenarios are verified.
2. RDS, S3, Terraform state, and corpus recovery boundaries are documented and tested where practical.
3. Application, architecture, runtime, GitOps, operations, and interview documents agree with the final system.
4. Sanitized evidence is complete.
5. Umbrella PR #32, the integration branch, release tag, and AWS resource retention decisions are finalized.

OpenSearch and ArgoCD are required completion items. They must not remain only as documentation, disabled configuration, or historical code.

## 3. Fixed architecture and non-regression decisions

The following decisions must remain true through all later phases:

- Spring Boot Backend owns the analysis lifecycle.
- The former Python analysis service is not restored as the default runtime.
- Cognito identity and RDB user mapping remain the authentication model.
- Flyway migrations and Hibernate validation remain the schema contract.
- S3 stores object content while RDB stores metadata and ownership state.
- EKS workloads use IRSA instead of static AWS credentials.
- External Secrets remains the secret-delivery boundary where already adopted.
- CloudFront remains the only public product entry; a direct public ALB is not added.
- Backend releases use immutable image digests.
- Bedrock timeout, output truncation, input rejection, and the single COMPACT retry behavior remain intact.
- Prompts, source images, embeddings, retrieved document text, generated Terraform, credentials, and Secrets are not written to logs or evidence.
- Existing upload, project list, project detail, analysis result, collaboration, authorization, visibility, and deletion behavior remains compatible.

The following legacy patterns must not be reintroduced:

- static AWS access keys
- credentials copied into process or Java system properties
- TLS certificate or hostname verification bypass
- hard-coded account, role, endpoint, or image values
- public OpenSearch or ArgoCD administration endpoints
- GitHub personal access tokens stored in cluster Secrets
- Terraform auto-approve as the normal release path
- direct `kubectl apply` or `kubectl set image` from the image-publish workflow
- rebuilding existing components from scratch without first evaluating current implementations

Older Terraformers, Infra-code, and rdb-refactor repositories are reuse-first design references. They do not override the current Spring Boot ownership model or justify restoring unsafe historical patterns.

## 4. Current implementation baseline

| Area | Current state | Remaining gap |
|---|---|---|
| Analysis ownership | `AnalysisRuntimeProperties` defaults to `INTEGRATED_JAVA`; a legacy Python mode and URL remain. | Confirm references and remove or isolate unused legacy configuration. |
| Generation context | `BedrockAnalysisProvider` calls `ReferenceRetriever` before the Bedrock request and returns retrieved document IDs. | Preserve the boundary and prove retrieved content reaches the generation prompt. |
| Embedding | `BedrockEmbeddingProvider` invokes a configured Bedrock embedding model. | Validate configuration and enforce embedding-dimension compatibility with the vector index. |
| Lexical retrieval | `backend/src/main/java/com/terraformers/modernization/reference/OpenSearchReferenceRetriever.java` is `@Primary` and sends unsigned lexical `multi_match`. | Retire or make it non-selectable for the completed RAG path. |
| Vector retrieval | `backend/src/main/java/com/terraformers/modernization/reference/opensearch/OpenSearchReferenceRetriever.java` embeds the query, builds k-NN search, and uses the signed client. | Make it the single selected runtime retriever and complete failure-policy tests. |
| AWS request identity | `SignedOpenSearchHttpClient` uses the default credential provider and SigV4. | Prove EKS IRSA and the `aoss` signing service against the live collection. |
| AOSS and corpus | No completed managed collection, compatible vector index, project-owned corpus, or repeatable ingestion path exists. | Implement and prove in Phase 3. |
| Backend image publication | The image workflow can build, publish, and resolve an ECR digest through GitHub OIDC. | Record that digest in Git without directly mutating the cluster. |
| Kubernetes image reference | `infra/kubernetes/base/backend-deployment.yaml` still contains a replacement image value. | Establish the canonical GitOps manifest and immutable digest update. |
| ArgoCD | No completed Backend Application, reconciliation evidence, rollback, or self-heal proof exists. | Implement and prove in Phase 4. |
| Operations | Existing probes and runtime evidence exist, but the full monitoring, continuity, failure, and recovery plan is incomplete. | Complete in Phase 6. |

No current runtime may claim completed vector RAG until a live project-owned corpus is ingested and signed AOSS top-K results are shown to affect generation.

## 5. Phase 0 — Close the frontend delivery baseline

This phase is a prerequisite checkpoint, not new frontend development.

Before Phase 2 live work proceeds, confirm:

1. A `frontend-delivery.yml` run was dispatched with `deploy_frontend=true`.
2. The deployed source commit corresponds to the frozen PR #53 baseline.
3. S3 synchronization succeeded.
4. CloudFront invalidation succeeded.
5. The live CloudFront UI shows the project card layout and project-detail deletion area.
6. Login, protected routes, project list, project detail, visibility, collaboration, analysis result, deletion, and logout remain usable.

A successful build-only workflow is not live-delivery evidence. Until the run and browser checks are recorded, PR #53 must not be described as confirmed live.

## 6. Phase 1 — Reuse decisions and roadmap baseline

The purpose of Phase 1 is to prevent redesign drift, not to preserve a detailed history of old runtime code.

The accepted outcome is:

- current Spring Boot analysis ownership remains canonical
- existing Java embedding, vector query, response parsing, signed HTTP, prompt, AnalysisJob, and S3 result boundaries are evaluated before new code is added
- Python service deployment is excluded
- current Terraform stages, Kubernetes overlays, image workflow, and frontend workflow are extended rather than replaced
- older repositories are consulted only when a current gap requires a reuse decision
- unsafe credential, TLS, public-access, PAT, direct-deployment, and auto-approve patterns are rejected
- Phases 2 through 7 below are the controlling roadmap

This document is the Phase 1 decision and completion-plan artifact.

## 7. Phase 2 — Complete the Spring Boot vector RAG path

### Goal

Complete one clear Java/Spring retrieval path using the existing Bedrock embedding, vector k-NN, signed OpenSearch client, and Bedrock prompt integration. This phase changes Backend code and tests only.

### Required work

1. Inspect the two OpenSearch retrievers and conditional bean selection.
2. Make the existing vector retriever the single selected `ReferenceRetriever` when retrieval is enabled.
3. Remove, retire, or explicitly isolate the lexical `@Primary` implementation.
4. Reuse the existing reference port, document model, prompt builder, response parser, k-NN builder, and signed client where suitable.
5. Introduce a retrieval-specific mode rather than overloading `AnalysisMode`.
6. Validate required configuration before analysis starts.
7. Define behavior for embedding failure, OpenSearch failure, response parsing failure, and empty results.
8. Add metadata-only retrieval observability.
9. Inspect remaining external-Python legacy references and remove or isolate unused paths without restoring Python deployment.
10. Add regression coverage for the current upload, AnalysisJob, S3 result, and result-query lifecycle.

### Retrieval mode contract

| Mode | Required behavior |
|---|---|
| `REQUIRED` | Embedding or retrieval failure fails the analysis job. Empty top-K is not silently accepted as success. This is the live E2E contract. |
| `OPTIONAL` | Retrieval failure permits generation without references and records sanitized failure metadata only. |
| `DISABLED` | Embedding and OpenSearch are not called. Use for local and constrained verification. |

### Safe observability

Permitted metadata includes analysis job ID, project ID, retrieval mode, embedding model ID, index alias/version, top-K, hit count, retrieved document IDs, outcome, error class, and elapsed time.

Do not log source images, prompts, embedding vectors, retrieved text, OpenSearch bodies, generated Terraform, credentials, or Secrets.

### Completion criteria

- exactly one vector retriever is selected when enabled
- embedding output reaches the k-NN request builder
- the signed OpenSearch request path is used
- retrieved `ReferenceDocument` content reaches the Bedrock prompt
- retrieved document IDs remain in the analysis result
- REQUIRED, OPTIONAL, and DISABLED behave as specified
- invalid endpoint, index, fields, model, or mode fails predictably
- sensitive content is absent from logs
- existing product and AnalysisJob behavior does not regress

### Out of scope

- AOSS creation or corpus ingestion
- Terraform or Kubernetes runtime changes
- ArgoCD installation
- image workflow changes
- live AWS deployment
- user-facing feature additions

## 8. Phase 3 — Provision AOSS and prove live RAG

### Goal

Provision the minimum secure OpenSearch Serverless environment, ingest a project-owned Terraform reference corpus, and prove live vector retrieval through Backend IRSA.

### Required infrastructure

Integrate into the current Terraform structure:

- AOSS encryption policy
- restricted network policy
- least-privilege data access policy
- `VECTORSEARCH` collection
- vector index and mapping
- Backend IRSA permissions
- runtime endpoint and index configuration
- bounded deployment and verification outputs

The Bedrock embedding output dimension and index vector dimension are one explicit contract. Incompatible model or dimension changes must fail validation.

Public AOSS access is not the default. Any service constraint that changes the network boundary must be explicitly reviewed and documented.

### Project-owned corpus

The corpus is small, curated, versioned, and limited to Terraformers-relevant patterns such as VPC/subnets, ALB/target groups, EKS/node groups, RDS subnet/security groups, S3/CloudFront, SQS, OpenSearch, IAM/IRSA, security-group relationships, common tags, and outputs.

Each document includes a stable ID, title, supported services, architecture pattern, Terraform guidance, security considerations, and source version. It must not include credentials, account IDs, live endpoints, tfstate, user uploads, or untracked external sample datasets.

### Ingestion requirements

Provide a repeatable and idempotent path that records corpus version, checksum, document count, embedding model, vector dimension, target collection/index, and outcome. Repeating the same version must not create uncontrolled duplicates.

### Live verification

1. Backend Pod uses ServiceAccount and IRSA.
2. Backend calls the configured Bedrock embedding model.
3. The signed request reaches AOSS using service name `aoss`.
4. A representative query returns top-K project-owned document IDs and hit count.
5. Retrieved documents are supplied to generation.
6. Retrieved document IDs are stored with the result.
7. The result is accessible through the existing CloudFront product path.
8. An intentional retrieval failure in REQUIRED mode produces the defined failed-job behavior.

### Completion evidence

- reviewed Terraform plan scope
- collection and index creation
- encryption, network, and data policy identifiers
- Backend IAM role and ServiceAccount association
- absence of static AWS keys
- corpus version, checksum, and document count
- retrieval mode, hit count, and document IDs
- analysis job ID and outcome
- browser upload, analysis, and result-query result
- expected cost, validation duration, retention, and cleanup record

Do not repeatedly destroy and recreate the environment to diagnose one failure. Fix the first actual failing boundary and repeat only necessary verification.

## 9. Phase 4 — Complete immutable-digest ArgoCD GitOps

### Goal

Make Git the Backend desired-state source and ArgoCD the release reconciler. GitHub Actions publishes the image and records the digest in Git; it does not directly deploy the Backend.

### Required release chain

1. GitHub Actions builds the Backend image.
2. GitHub OIDC authorizes ECR publication.
3. The workflow pushes the image and resolves the immutable digest.
4. The approved GitOps manifest is updated to that digest.
5. The change is committed through a bounded branch or approved automation path.
6. ArgoCD tracks the actual repository, revision, and canonical manifest path.
7. ArgoCD reconciles the change to EKS.
8. The Application becomes `Synced` and `Healthy`.
9. Git digest, Deployment image, and Pod runtime image ID match.
10. The CloudFront product path passes smoke verification.

The workflow must not deploy with `kubectl apply`, `kubectl set image`, or equivalent direct mutation.

### ArgoCD requirements

- pin the ArgoCD version
- define installation and upgrade boundaries
- avoid a public internet-facing administration endpoint
- use authenticated operational access
- track the actual repository and canonical Backend manifest path
- enable automated sync, prune, and self-heal only after scope review
- avoid GitHub PAT and static AWS credentials in cluster Secrets
- protect image updates from concurrent runs and self-trigger loops
- keep frontend S3/CloudFront delivery separate from Backend GitOps

### Rollback and self-heal

Rollback uses Git history: record the current digest, reconcile a new digest, verify browser/runtime state, revert the manifest commit, verify the previous digest returns, and repeat browser smoke.

Self-heal creates one bounded and reversible drift in an Application-owned, non-secret field and proves ArgoCD restores the Git value without public exposure or uncontrolled downtime.

### Completion evidence

- workflow run and source commit
- ECR repository and digest
- manifest-update commit
- ArgoCD revision, `Synced`, and `Healthy`
- Deployment generation and Pod image ID
- browser smoke result
- rollback commit and restored digest
- self-heal observation

## 10. Phase 5 — Application, interview, and repository alignment

After the live RAG and GitOps chain is proven, update documentation so the repository, portfolio, application, and interview explanation describe the same system.

Required artifacts include:

- `docs/application-alignment.md`
- `docs/rag-runtime.md`
- `docs/gitops-delivery.md`
- `docs/live-runtime-baseline.md`
- `docs/feature-freeze.md`
- `docs/operations-hardening-plan.md`
- README and project direction documents
- architecture and validation documents
- deployment, rollback, recovery, and operations runbooks
- interview evidence and PR #32 summary

Documentation must distinguish:

- work performed during the 2024 five-person team project
- later modernization performed after the team project
- personal implementation from team-owned components
- source merge from image publication, manifest update, rollout, browser E2E, rollback, and recovery

Later modernization must not be represented as work completed in 2024, and the whole service must not be described as a solo implementation.

## 11. Phase 6 — Operations hardening

### Observability

- CloudWatch dashboard and alarms for the Backend and relevant AWS boundaries
- OpenSearch retrieval metrics and failure signals without sensitive content
- ArgoCD sync, health, reconciliation, and drift signals
- correlation by analysis job ID, safe request ID, deployment revision, and image digest

### Availability and traffic continuity

- review Backend replica count against cost and node capacity
- confirm startup, readiness, and liveness probes
- add or review a PodDisruptionBudget where meaningful
- verify one Pod failure does not produce avoidable product-path downtime
- avoid claiming high availability beyond the actual node, replica, database, and ingress design

### Controlled failure scenarios

Validate bounded failures for:

- Backend Pod
- database connection or availability
- OpenSearch retrieval
- Bedrock invocation
- ArgoCD reconciliation or manifest drift

Each scenario records the first failing boundary, user-visible effect, alert or evidence, recovery action, and restored state. Do not create uncontrolled destructive tests.

### Recovery boundaries

Document and verify practical recovery for:

- RDS data and schema
- S3 source and result objects
- Terraform remote state and locking assumptions
- OpenSearch corpus source, version, and repeatable re-ingestion
- GitOps desired state and rollback history

### Completion criteria

- monitoring and alarm evidence exists
- probe and continuity behavior is verified
- controlled failures produce expected boundaries
- recovery steps restore the required state
- cost, retention, and cleanup decisions are explicit
- sanitized evidence and runbooks can be used in an interview without exposing secrets

## 12. Phase 7 — Final closure

The project closes only after:

1. all required sanitized evidence is collected
2. Phase 5 documentation and Phase 6 operations evidence are complete
3. PR #32 is updated to reflect the final code, infrastructure, deployment, and validation state
4. Draft status is removed only after all completion gates are met
5. the integration branch is merged to `main`
6. a release tag is created
7. temporary branches and artifacts are reviewed
8. AWS resources are explicitly marked for retention, scale-down, or deletion
9. corpus, state, database, and object retention decisions are recorded
10. the final browser and runtime baseline is recorded

A source merge alone does not complete the project.

## 13. Final integrated scenarios

### 13.1 RAG and GitOps scenario

1. An authenticated user uploads an architecture image through CloudFront.
2. Backend creates an AnalysisJob and reads the source from S3.
3. Bedrock analyzes the input.
4. Bedrock embedding and AOSS top-K retrieval run in REQUIRED mode.
5. Project-owned document IDs and hit count are returned.
6. Retrieved content reaches generation.
7. Terraform output is stored and viewed through the existing UI.
8. A new Backend image is published to ECR.
9. Its digest is recorded in Git.
10. ArgoCD reconciles it to EKS and becomes `Synced` and `Healthy`.
11. Git, Deployment, and Pod runtime digests match.
12. Browser smoke passes.
13. Git revert restores the previous digest and browser smoke passes again.
14. A bounded drift is corrected by self-heal.

### 13.2 Operations scenario

1. Monitoring shows the healthy baseline.
2. One bounded component failure is introduced.
3. The first actual failing boundary and user-visible effect are observed.
4. Alerts or safe evidence identify the failure.
5. The documented recovery path is executed.
6. Runtime, data, digest, and browser state return to the expected baseline.

## 14. Evidence and security rules

Evidence must distinguish:

- source merged
- image published
- manifest updated
- ArgoCD synced
- workload healthy
- runtime digest matched
- browser E2E passed
- rollback passed
- self-heal passed
- controlled failure observed
- recovery passed

Evidence may include commit SHA, workflow run ID, ECR repository/digest, ArgoCD revision/status, Deployment generation, Pod image ID, analysis job ID, retrieval mode, hit count, document IDs, corpus version, alarm state, elapsed time, and outcome.

Evidence must not include access keys, tokens, passwords, kubeconfig, raw tfvars, tfstate, Terraform plan JSON, source images, prompts, vectors, retrieved text, generated Terraform text, or user-uploaded originals.

## 15. Execution discipline

- Work one phase at a time and keep each implementation PR meaningful but bounded.
- Reuse existing source, workflow, manifests, and scripts before adding new ones.
- Do not add user features to prove infrastructure work.
- Do not perform Terraform apply, ArgoCD installation, cluster mutation, deployment, or merge without explicit approval.
- Diagnose the first actual failure instead of adding broad preflight gates or repeated recovery scripts.
- Distinguish source, image, manifest, reconciliation, runtime, browser, rollback, and recovery states.
- Review expected cost, retention, and cleanup before creating cost-bearing resources.
- User approval remains required for GitHub Actions dispatch, Terraform/AWS/Kubernetes mutation, and live browser verification.

## 16. Immediate next work

After this documentation PR is merged:

1. close the Phase 0 frontend-delivery evidence if it is still unresolved
2. create one Phase 2 Backend PR limited to:
   - resolving lexical/vector retriever bean selection
   - making the existing vector retriever the selected path
   - introducing the separate retrieval mode contract
   - implementing REQUIRED, OPTIONAL, and DISABLED behavior
   - validating retrieval configuration
   - adding metadata-only observability
   - proving embedding → k-NN → retrieved documents → Bedrock prompt through tests
   - removing or isolating unused external-Python legacy references
   - preserving current product behavior and AnalysisJob/S3 result flow

That Phase 2 PR must not change Terraform, AOSS resources, corpus ingestion, Kubernetes runtime configuration, ArgoCD, Backend image publication, frontend delivery, AWS resources, live deployment, or user-facing functionality.

## 15. Phase 3 infrastructure and corpus foundation

PR #55 completed Phase 2's Java/Spring signed vector retrieval path. The Phase 3 foundation adds a separately reviewable Terraform contract for one classic private OpenSearch Serverless `VECTORSEARCH` collection and a project-owned versioned corpus; it is not a live deployment or an alternate analysis service.

The RAG root pins `hashicorp/aws` to `= 5.100.0`. It intentionally does not move other roots to provider 6.x or use NextGen collection groups. The collection has AWS-owned encryption, disabled standby replicas, explicit tags, and a private VPC endpoint. Its network policy contains only the collection resource and that endpoint—never public access, Dashboards exposure, or a Bedrock Knowledge Bases service exception.

The backend's existing IRSA role gets read-only AOSS data access via a separate attached runtime policy. A GitHub Environment OIDC corpus-ingestion role has exact audience and subject conditions and scoped write access. The versioned corpus and index schema fix Titan v2 at 1024 dimensions, `terraformers-reference-v1`, `embedding`, and `content`. Actual index creation, upload, embedding, ingestion, signed live query, rollout, and browser E2E remain later boundaries.

Before apply, review the Terraform plan and generate any lock file with the Terraform CLI rather than inventing checksums. After apply, use a short verification window and decide retention or cleanup; do not repeatedly destroy and recreate AOSS. Fix the first failing boundary only before continuing. Expected costs after apply are AOSS capacity/network, S3 version storage, and later Bedrock embedding calls. The still-unrecorded frontend browser smoke remains a prerequisite before a live Phase 3 apply.
