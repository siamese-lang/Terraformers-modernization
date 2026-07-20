# Terraformers RAG and GitOps Completion Plan

## 1. Purpose

Terraformers-modernization is the operational modernization of the 2024 AWS Cloud School Terraformers team project. It is not a replacement product and does not add a second analysis service or a separate demonstration UI.

The project is complete only when the existing architecture-image analysis flow is proven through the following operating chain:

1. The Spring Boot Backend owns the analysis job lifecycle.
2. Bedrock analyzes the uploaded architecture image.
3. The Backend creates an embedding for retrieval.
4. OpenSearch Serverless returns relevant project-owned Terraform reference documents through vector k-NN search.
5. Retrieved documents are supplied to the Terraform generation context.
6. GitHub Actions publishes the Backend image to ECR with an immutable digest.
7. The digest is recorded in Git-managed Kubernetes manifests.
8. ArgoCD reconciles the manifest to EKS.
9. Git, ArgoCD, Deployment, and Pod runtime digests are verified to match.
10. Browser smoke, Git-revert rollback, and ArgoCD self-heal are demonstrated.

OpenSearch and ArgoCD are required completion items, not optional documentation or historical references.

## 2. Fixed architecture decisions

### 2.1 Spring Boot remains the analysis runtime

The current Java/Spring Backend remains the canonical analysis runtime. The former separated Python analysis service is not restored as the default runtime.

The existing `AnalysisMode` continues to describe analysis ownership:

- `INTEGRATED_JAVA`
- `EXTERNAL_PYTHON_LEGACY`

Phase 2 must inspect the remaining legacy Python mode and URL references. Unused legacy paths should be removed or clearly isolated, but Python service deployment is not part of the completion plan.

### 2.2 Existing user functionality is frozen

No new user-facing feature is required. The project must preserve the existing upload, project list, project detail, analysis result, collaboration, authorization, and deletion flows.

RAG and GitOps work must be proven through the existing product path rather than through a separate test-only UI.

### 2.3 Reuse current implementations before adding new ones

The following current boundaries are the starting point and should be reused unless a concrete defect requires a bounded change:

- `backend/src/main/java/com/terraformers/modernization/analysis/AnalysisRuntimeProperties.java`
- `backend/src/main/java/com/terraformers/modernization/analysis/AnalysisMode.java`
- `backend/src/main/java/com/terraformers/modernization/analysis/bedrock/BedrockAnalysisProvider.java`
- `backend/src/main/java/com/terraformers/modernization/analysis/bedrock/BedrockPromptBuilder.java`
- `backend/src/main/java/com/terraformers/modernization/reference/ReferenceRetriever.java`
- `backend/src/main/java/com/terraformers/modernization/reference/ReferenceQuery.java`
- `backend/src/main/java/com/terraformers/modernization/reference/ReferenceDocument.java`
- `backend/src/main/java/com/terraformers/modernization/reference/BedrockEmbeddingProvider.java`
- `backend/src/main/java/com/terraformers/modernization/reference/opensearch/OpenSearchReferenceRetriever.java`
- `backend/src/main/java/com/terraformers/modernization/reference/opensearch/OpenSearchKnnQueryBuilder.java`
- `backend/src/main/java/com/terraformers/modernization/reference/opensearch/OpenSearchResponseParser.java`
- `backend/src/main/java/com/terraformers/modernization/reference/opensearch/SignedOpenSearchHttpClient.java`
- the existing `AnalysisJob` lifecycle and S3 source/result flow
- the existing Terraform stages and Kubernetes base/overlay structure
- `.github/workflows/backend-image-publish.yml`
- `.github/workflows/frontend-delivery.yml`

Older Terraformers, Infra-code, and rdb-refactor implementations are design references only. They do not override the current Spring Boot ownership model or justify restoring unsafe deployment patterns.

The following legacy patterns must not be reused:

- static AWS access keys
- credentials copied into process or Java system properties
- TLS certificate or hostname verification bypass
- hard-coded account, role, endpoint, or image values
- public OpenSearch or ArgoCD administration endpoints
- GitHub personal access tokens stored in cluster Secrets
- Terraform auto-approve as the normal release path
- direct `kubectl apply` or `kubectl set image` from the image workflow
- logs containing prompts, embedding vectors, retrieved document text, generated Terraform, or Secrets

## 3. Current implementation baseline

| Area | Current state | Remaining gap |
|---|---|---|
| Analysis ownership | `AnalysisRuntimeProperties` defaults to `INTEGRATED_JAVA`; a legacy Python mode and URL remain. | Confirm references and remove or isolate unused legacy configuration. |
| Generation context | `BedrockAnalysisProvider` calls `ReferenceRetriever` before building the Bedrock request and returns retrieved document IDs with the analysis result. | Preserve this boundary and prove retrieved content reaches the generation prompt. |
| Embedding | `BedrockEmbeddingProvider` invokes a configured Bedrock embedding model. | Validate configuration and enforce embedding-dimension compatibility with the vector index. |
| Lexical retrieval | `backend/.../reference/OpenSearchReferenceRetriever.java` is `@Primary` and sends an unsigned lexical `multi_match` request. | Retire or make it non-selectable for the completed RAG path. |
| Vector retrieval | `backend/.../reference/opensearch/OpenSearchReferenceRetriever.java` embeds the query, builds k-NN search, and uses the signed OpenSearch client. | Make this the single selected runtime retriever and complete tests and failure policy. |
| AWS request identity | `SignedOpenSearchHttpClient` uses the AWS default credential provider and SigV4 signing. | Prove the EKS workload uses IRSA and the `aoss` signing service against the live collection. |
| AOSS and corpus | No current managed collection, compatible vector index, project-owned corpus, or repeatable ingestion path is complete. | Implement in Phase 3. |
| Backend image publication | The image workflow can build, publish, and resolve an ECR digest through GitHub OIDC. | Record that digest in the Git-managed manifest without directly mutating the cluster. |
| Kubernetes image reference | `infra/kubernetes/base/backend-deployment.yaml` still contains a replacement image value rather than the completed GitOps digest chain. | Establish the canonical manifest path and immutable digest update. |
| ArgoCD | No completed Backend Application, reconciliation evidence, rollback, or self-heal proof exists. | Implement in Phase 4. |

No current runtime may claim completed vector RAG until a live project-owned corpus is ingested and the signed AOSS top-K result is shown to affect generation.

## 4. Phase 2 — Complete the Spring Boot vector RAG path

### 4.1 Goal

Complete one clear Java/Spring retrieval path using the existing Bedrock embedding, vector k-NN, signed OpenSearch client, and Bedrock prompt integration. This phase changes Backend code and tests only.

### 4.2 Required work

1. Inspect the two OpenSearch retrievers and their conditional bean selection.
2. Make the existing vector retriever the single selected `ReferenceRetriever` when retrieval is enabled.
3. Remove, retire, or explicitly isolate the lexical `@Primary` implementation so it cannot silently replace vector search.
4. Keep the existing reference port, document model, prompt builder, response parser, k-NN builder, and signed client where they already satisfy the target.
5. Introduce a retrieval-specific mode rather than overloading `AnalysisMode`.
6. Validate required configuration before an analysis starts.
7. Define failure behavior for embedding, OpenSearch request, response parsing, and empty results.
8. Add safe retrieval observability using metadata only.
9. Inspect the remaining external-Python legacy references and remove or isolate unused paths without restoring a Python service.
10. Add regression coverage proving the existing upload and analysis lifecycle still behaves correctly.

### 4.3 Retrieval mode contract

Use a separate `RagMode` or `RetrievalMode` with the following behavior:

| Mode | Required behavior |
|---|---|
| `REQUIRED` | Embedding or retrieval failure fails the analysis job. This is the production live-E2E contract. |
| `OPTIONAL` | Retrieval failure permits generation without references. Record sanitized failure metadata only. |
| `DISABLED` | Do not call the embedding model or OpenSearch. Use for local and constrained verification. |

The implementation must not treat an empty top-K result as a successful REQUIRED retrieval unless the contract explicitly defines that outcome and tests it.

### 4.4 Safe observability

Permitted fields include:

- analysis job ID
- project ID
- retrieval mode
- embedding model ID
- index alias or version
- top-K request value
- hit count
- retrieved document IDs
- request outcome
- error class
- elapsed time

Do not log source images, prompts, embedding vectors, retrieved document text, OpenSearch response bodies, generated Terraform, credentials, or Secrets.

### 4.5 Completion criteria

Phase 2 is complete when tests prove all of the following:

- exactly one vector retriever is selected when retrieval is enabled
- the embedding result reaches the k-NN request builder
- the signed OpenSearch request path is used
- retrieved `ReferenceDocument` content reaches the Bedrock prompt builder
- retrieved document IDs remain in the analysis result
- REQUIRED, OPTIONAL, and DISABLED behave as specified
- invalid endpoint, index, field, model, or mode configuration fails predictably
- prompt, vector, retrieved text, and generated Terraform do not appear in logs
- existing upload, analysis-job, result-storage, and result-query behavior does not regress

### 4.6 Out of scope

Phase 2 does not:

- create AOSS resources
- ingest a live corpus
- change Terraform or Kubernetes runtime configuration
- install ArgoCD
- change the image publication workflow
- add user-facing features
- deploy or run live AWS E2E

## 5. Phase 3 — Provision AOSS and prove live RAG

### 5.1 Goal

Provision the minimum secure OpenSearch Serverless environment, ingest a project-owned Terraform reference corpus, and prove that the existing Backend performs live vector retrieval through IRSA.

### 5.2 Required infrastructure

Integrate the following into the current Terraform structure rather than creating an unrelated stack:

- AOSS encryption policy
- restricted network policy
- least-privilege data access policy
- `VECTORSEARCH` collection
- vector index and mapping
- Backend IRSA permissions
- runtime endpoint and index configuration
- outputs needed for bounded deployment and verification

The embedding model output dimension and index vector dimension must be one explicit contract. A model or dimension change must fail validation rather than producing an incompatible live index.

Public AOSS access is not the default target. Where an AWS service constraint requires a specific network path, document the exact boundary and keep administration and data access restricted.

### 5.3 Project-owned corpus

The corpus must be small, curated, versioned, and relevant to Terraformers. Candidate patterns include:

- VPC and subnet layout
- ALB and target groups
- EKS and node groups
- RDS subnet and security groups
- S3 and CloudFront
- SQS
- OpenSearch
- IAM roles and IRSA
- security-group relationships
- common tags and outputs

Each document should contain:

- stable document ID
- title
- supported AWS services
- architecture pattern
- Terraform guidance
- security considerations
- source version

The corpus must not include credentials, account identifiers, live endpoints, tfstate, user uploads, or copied external sample datasets used without provenance.

### 5.4 Ingestion requirements

Provide a repeatable and idempotent ingestion path that records:

- corpus version
- checksum
- document count
- embedding model
- vector dimension
- target collection and index identifier
- ingestion outcome

Repeated ingestion of the same corpus version must not create uncontrolled duplicate documents.

### 5.5 Live verification

The live E2E must prove the following chain:

1. The Backend Pod uses its ServiceAccount and IRSA, not static credentials.
2. The Backend calls the configured Bedrock embedding model.
3. The signed request reaches the AOSS vector index using the `aoss` signing service.
4. A representative query returns top-K project-owned document IDs.
5. Retrieved documents are supplied to generation.
6. The analysis result stores retrieved document IDs.
7. The generated result is accessible through the existing CloudFront product flow.
8. In REQUIRED mode, an intentional retrieval failure produces the defined failed-job behavior.

### 5.6 Completion evidence

- reviewed Terraform plan scope
- collection and index creation result
- encryption, network, and data access policy identifiers
- Backend IAM role and ServiceAccount association
- absence of static AWS keys
- corpus version, checksum, and document count
- live retrieval mode, hit count, and document IDs
- analysis job ID and outcome
- browser upload, analysis, and result-query result
- cost and cleanup record

### 5.7 Cost and cleanup

Before applying AOSS changes, document:

- expected collection capacity cost
- expected verification duration
- Bedrock invocation scope
- whether the collection and corpus will remain after validation
- cleanup order for index, collection, policies, and temporary evidence
- data that must be retained before cleanup

Do not repeatedly destroy and recreate the entire environment to diagnose one failure. Fix the first actual failing boundary and repeat only the necessary verification.

## 6. Phase 4 — Complete immutable-digest ArgoCD GitOps

### 6.1 Goal

Make Git the desired-state source for the Backend image and make ArgoCD the release reconciler. GitHub Actions publishes the image and records the digest in Git; it does not directly deploy the Backend.

### 6.2 Required release chain

1. GitHub Actions builds the Backend image.
2. GitHub OIDC authorizes ECR publication.
3. The workflow pushes the image and resolves its immutable digest.
4. The approved GitOps manifest is updated to that digest.
5. The Git change is committed through a bounded branch or approved automation path.
6. ArgoCD tracks the actual repository, revision, and manifest path.
7. ArgoCD reconciles the change to EKS.
8. The Application becomes `Synced` and `Healthy`.
9. The Git digest, Deployment image, and Pod runtime image ID are verified to match.
10. The existing CloudFront product path passes smoke verification.

The workflow must not deploy the Backend with `kubectl apply`, `kubectl set image`, or an equivalent direct mutation.

### 6.3 ArgoCD requirements

- pin the ArgoCD version
- define the installation and upgrade boundary
- avoid a public internet-facing administration endpoint
- use authenticated operational access
- configure the Backend Application against the actual repository and canonical manifest path
- enable automated sync, prune, and self-heal only after the tracked scope is reviewed
- avoid GitHub PAT and static AWS credentials in cluster Secrets
- protect the image-update workflow against concurrent runs and self-trigger loops
- keep frontend S3/CloudFront delivery separate from Backend GitOps

### 6.4 Rollback and self-heal

Rollback proof must use Git history:

1. Record the current Git and runtime digest.
2. Publish and reconcile a new Backend digest.
3. Confirm browser smoke and runtime digest equality.
4. Revert the manifest commit to the prior digest.
5. Confirm ArgoCD returns to `Synced` and `Healthy`.
6. Confirm the previous runtime digest is restored.
7. Repeat browser smoke.

Self-heal proof must create a bounded, reversible drift in a field owned by the Application and show that ArgoCD restores the Git value. The test must not expose public traffic, alter Secrets, or create uncontrolled downtime.

### 6.5 Completion evidence

- workflow run ID
- source commit SHA
- ECR repository and digest
- manifest-update commit SHA
- ArgoCD Application revision
- `Synced` and `Healthy` status
- Deployment generation
- Pod image ID
- browser smoke result
- rollback commit and restored digest
- self-heal observation

## 7. Final integrated completion scenario

The project may claim completion only after one integrated scenario proves:

1. An authenticated user uploads an architecture image through the existing CloudFront entry.
2. The Backend creates an analysis job and reads the source from S3.
3. Bedrock analyzes the architecture input.
4. Bedrock embedding and AOSS top-K vector retrieval run in REQUIRED mode.
5. Project-owned reference document IDs are returned.
6. Retrieved content is supplied to generation.
7. Terraform output is generated and stored through the existing result flow.
8. The user reads the result through the existing project UI.
9. A new Backend image is published to ECR.
10. Its immutable digest is recorded in the Git manifest.
11. ArgoCD reconciles the manifest to EKS.
12. ArgoCD is `Synced` and `Healthy`.
13. Git, Deployment, and Pod runtime digests match.
14. The existing CloudFront smoke scenario passes.
15. A Git revert restores the prior digest.
16. ArgoCD reconciles the rollback and the product still works.
17. A bounded drift is corrected by ArgoCD self-heal.

## 8. Evidence and security rules

Evidence must distinguish these states rather than treating them as equivalent:

- source merged
- image published
- manifest updated
- ArgoCD synced
- workload healthy
- runtime digest matched
- browser E2E passed
- rollback passed
- self-heal passed

Evidence may include:

- commit SHA
- workflow run ID
- ECR repository and digest
- ArgoCD status and revision
- Deployment generation
- Pod image ID
- analysis job ID
- retrieval mode
- hit count
- retrieved document IDs
- corpus version
- elapsed time and outcome

Evidence must not include:

- access keys or tokens
- passwords
- kubeconfig
- raw tfvars
- tfstate
- Terraform plan JSON
- source images
- prompts
- embedding vectors
- retrieved document text
- generated Terraform text
- user-uploaded original content

## 9. Execution discipline

- Work one phase at a time.
- Prefer extending existing code and manifests over creating parallel implementations.
- Do not add a new user feature to prove infrastructure work.
- Do not automate live Terraform apply, ArgoCD installation, or cluster mutation before the relevant plan and scope are reviewed.
- Diagnose the first actual failure rather than adding broad preflight gates or repeated recovery scripts.
- Distinguish source merge, image publication, Git manifest update, ArgoCD reconciliation, runtime rollout, and browser verification.
- Review cost, retention, and cleanup before creating cost-bearing resources.

## 10. Immediate next PR

The next implementation PR is Phase 2 only.

Its scope is limited to:

- resolve the current lexical/vector retriever bean-selection conflict
- make the existing vector retriever the selected path
- introduce the separate retrieval mode contract
- implement REQUIRED, OPTIONAL, and DISABLED behavior
- validate required retrieval configuration
- add safe metadata-only observability
- prove embedding → k-NN → retrieved documents → Bedrock prompt through tests
- inspect and remove or isolate unused external-Python legacy references
- preserve the current user-facing behavior and AnalysisJob/S3 result lifecycle

The next PR must not change:

- Terraform
- AOSS resources or corpus ingestion
- Kubernetes runtime configuration
- ArgoCD
- Backend image publication
- frontend delivery
- AWS resources
- live deployment
- user-facing functionality
