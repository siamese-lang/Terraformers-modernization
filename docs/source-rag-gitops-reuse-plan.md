# Phase 1: RAG·AOSS·ArgoCD Source Reuse Plan

## 1. Purpose and project identity

Terraformers-modernization is the operational modernization of the 2024 AWS Cloud School five-person **Terraformers** team project, not a replacement product. Bedrock embedding, OpenSearch/AOSS vector retrieval whose documents are supplied to generation, EKS backend, S3/CloudFront, Terraform-managed AWS resources, ECR publishing, immutable-digest GitOps, ArgoCD sync, runtime-digest verification, and Git-revert rollback are required completion evidence. OpenSearch and ArgoCD are therefore required completion items, not optional historical documentation.

This Phase 1 change is an evidence and decision inventory only. It neither changes runtime, Terraform, workflows, nor Kubernetes resources.

## 2. Inspection scope and exact commits

| Repository | Requested commit | Read-only availability result | Evidence used in this plan |
|---|---|---|---|
| `siamese-lang/Terraformers-modernization` | `1c7377747fd2921f3f174c51f22167b1af5ead83` | present locally; `HEAD` resolved exactly to it before branch creation | source and manifests at that commit |
| `AWS-Terraformers/Terraformers` | `4081f2f8181b197608cbeb3c6c10ccd12edb384e` | not present locally; read-only HTTPS clone was refused by the environment proxy (403) | path-level inventory recorded below, and prior in-repository source-audit references; no latest revision was substituted |
| `AWS-Terraformers/Infra-code` | `a4aeda2b8a7a82888bc61c299deab97d9cbeb8cb` | not present locally; same proxy refusal | path-level inventory recorded below, and prior in-repository source-audit references; no latest revision was substituted |
| `siamese-lang/rdb-refactor` | `46eeeeb505f996d6316ea22ae54d9db62c9cf1e7` | not present locally; same proxy refusal | current repository's reuse audit; no latest revision was substituted |

The unavailable three commits are explicitly retained as the intended inspection baselines, rather than silently mixing another revision. Before Phase 2--4 implementation, an environment with read-only access must re-run the path checks at these exact SHAs and replace any path-level legacy observations that cannot be independently reproduced.

## 3. Runtime-path determination method

A source file is treated as runtime only when an entrypoint, deployment manifest, workflow, controller call chain, or Spring bean selection reaches it. A copied directory, unused class, or Terraform module is not runtime merely because it exists. The determination order is: (1) container `CMD`/`ENTRYPOINT`; (2) upload controller-to-service call chain; (3) active Spring conditional beans and `@Primary`; (4) deployed manifest/workflow references; and (5) tests/configuration only as supporting evidence.

## 4. Original Terraformers RAG inventory

| Exact path at `4081f2…` | Observed/required determination | Runtime connection evidence | Classification | Current treatment |
|---|---|---|---|---|
| `python/Dockerfile` | The Dockerfile entrypoint is the controlling evidence for the historical Python container; it must decide historical runtime, not the presence of other Python files. | Must be verified by `CMD`/`ENTRYPOINT` at the stated SHA; unavailable in this environment. | `NOT_ACTUALLY_IN_RUNTIME` pending exact-entrypoint verification | Do not restore Python as default runtime. |
| `python/bedrock.py`, `python/bedrock_v5.py` | Alternative implementations are code presence, not proof that the image invoked either one. | No locally reproducible container-entrypoint evidence. | `NOT_ACTUALLY_IN_RUNTIME` | Reuse only the embedding → retrieval → context concept after source verification. |
| `backend/mini/src/main/java/com/amazoonS3/mini/controller/FileUploadController.java` | Upload path must be followed from request handler to the actual analysis invocation. | The existence of `InfrastructureAnalysisService` alone does not establish this call. | `NOT_ACTUALLY_IN_RUNTIME` pending call-chain verification | Phase 2 retains Backend-owned lifecycle. |
| `backend/mini/src/main/java/com/amazoonS3/mini/service/InfrastructureAnalysisService.java` | It contains a historical RAG flow, but whether upload invoked it is an independent question. | No locally reproducible controller call-chain evidence. | `REUSE_CONCEPT_ONLY` | Reuse the bounded RAG sequence only; do not copy its credentials/logging/client construction. |
| `backend/mini/src/rag-using-langchain-amazon-bedrock-and-opensearch/` | External sample directory with a public endpoint and external dataset; it is not a Terraformers production corpus/runtime proof. | Its separate sample location is not an application entrypoint. | `REMOVE`, `NOT_ACTUALLY_IN_RUNTIME` | Do not restore it; build a curated, project-owned corpus in Phase 3. |

Legacy patterns to remove when the exact source is available include static access keys, credentials copied into Java system properties, TLS hostname-verification bypass, hard-coded account/role/endpoint values, and logging of sensitive content.

## 5. Infra-code AOSS inventory

| Exact path at `a4aeda…` | Observed design unit | Runtime connection evidence | Classification | Current treatment |
|---|---|---|---|---|
| `modules/aoss/` | AOSS collection plus encryption, network, and data-access-policy topology; vector index mapping/dimension must be read together with the writer. | Terraform topology is infrastructure intent, not proof of a populated live index. | `MODERNIZE` | Retain topology concepts; define index mapping and dimension from the chosen embedding model; private/restricted network and least-privilege data access only. |
| `modules/bedrock/` | Bedrock permissions/configuration concept. | Module existence does not connect embedding to a live k-NN index. | `REUSE_CONCEPT_ONLY` | Use IRSA credential chain and narrow Bedrock permissions. |
| `kubernetes/` AOSS-related configuration | Backend runtime configuration/identity connection. | Must be traced to a ServiceAccount and deployed workload. | `MODERNIZE` | Add only in Phase 3 after collection, policy, index, corpus, and ingestion exist. |

A public AOSS network policy is not reusable. AOSS requests require the backend workload's IRSA-based default credential chain and SigV4 signing (`aoss`), with no static keys.

## 6. Infra-code ArgoCD and workflow inventory

| Exact path at `a4aeda…` | Observed design unit | Runtime connection evidence | Classification | Current treatment |
|---|---|---|---|---|
| `modules/argocd/` | ArgoCD Application(s), including Backend/Bedrock Application intent and automated sync, prune, and self-heal concepts. | An Application only connects if it tracks the actual repository and manifest path. | `MODERNIZE` | Reuse automated sync/prune/selfHeal concept; bind it to this repository's actual GitOps path in Phase 4. |
| `.github/workflows/terraform-cicd.yml` | Terraform CI/CD workflow. Auto-approve or direct cluster mutation is not immutable-digest GitOps. | No manifest digest commit plus Argo Application tracking establishes the required chain. | `REUSE_CONCEPT_ONLY` | Keep validation concepts only; no static AWS keys, PAT, auto-approve, or direct `kubectl` deployment. |
| `kubernetes/` ArgoCD ingress/manifests | Public ingress and `--insecure` are legacy exposure choices. | Ingress settings do not prove reconciliation. | `REMOVE` | Private/authenticated operational access; no public ingress or `--insecure`. |
| ECR/EKS/IAM/Secrets configuration | ECR, EKS, IAM, and Secret boundaries are reusable topology inputs. | Static AWS credential Secrets and GitHub PAT are not runtime identity evidence acceptable today. | `MODERNIZE`, `REMOVE` | GitHub OIDC for publish; IRSA for runtime; secret references only. |

## 7. rdb-refactor reuse inventory

`rdb-refactor` at `46eeeeb505f996d6316ea22ae54d9db62c9cf1e7` remains the canonical reference for RDB/domain/persistence: users/identity mapping, projects, ownership, file tree, runs, collaboration, foreign keys, status/soft-delete, and persistence access patterns. Classification: `REUSE_AS_IS` for the canonical domain decision, with normal modernization adaptation where current package boundaries require it.

Any copied Terraformers Python RAG code, copied/modified AOSS module, modified ArgoCD module, or operational document in that repository is **not** canonical runtime merely because it was copied. Classification: `NOT_ACTUALLY_IN_RUNTIME` plus `REUSE_CONCEPT_ONLY` until exact-sha source and active deployment links are verified. It cannot override the current Backend ownership decision.

## 8. Current Modernization inventory

| Exact current path | Observed behavior and connection | Classification | Treatment |
|---|---|---|---|
| `backend/src/main/java/com/terraformers/modernization/analysis/AnalysisRuntimeProperties.java` | Has Bedrock embedding/OpenSearch settings and an external-Python legacy URL, but `AnalysisMode` contains only `INTEGRATED_JAVA` and `EXTERNAL_PYTHON_LEGACY`; REQUIRED/OPTIONAL/DISABLED do not exist. | `MODERNIZE` | Add a separate retrieval-mode contract in Phase 2; do not overload analysis ownership mode. |
| `backend/src/main/java/com/terraformers/modernization/analysis/bedrock/BedrockAnalysisProvider.java` and `backend/src/main/java/com/terraformers/modernization/analysis/bedrock/BedrockPromptBuilder.java` | Retrieves `ReferenceDocument`s before building the Bedrock prompt; reference content is included in the prompt. | `REUSE_AS_IS` | Preserve this Backend-owned connection, with safe metadata-only observability. |
| `backend/src/main/java/com/terraformers/modernization/reference/ReferenceRetriever.java`, `backend/src/main/java/com/terraformers/modernization/reference/ReferenceQuery.java`, and `backend/src/main/java/com/terraformers/modernization/reference/ReferenceDocument.java` | Stable retrieval port/query/document boundary. | `REUSE_AS_IS` | Retain and extend for vector retrieval. |
| `backend/src/main/java/com/terraformers/modernization/reference/BedrockEmbeddingProvider.java` | Invokes Bedrock embedding, conditionally enabled. | `MODERNIZE` | Inject/configure client and prove model dimension/index compatibility. |
| `backend/src/main/java/com/terraformers/modernization/reference/OpenSearchReferenceRetriever.java` | `@Primary` bean sends an unsigned lexical `multi_match` HTTP query. This wins bean selection when enabled. | `MODERNIZE` | Replace/retire as active path; lexical retrieval is not completed vector RAG. |
| `backend/src/main/java/com/terraformers/modernization/reference/opensearch/OpenSearchReferenceRetriever.java`, `OpenSearchKnnQueryBuilder.java`, `OpenSearchResponseParser.java`, and `SignedOpenSearchHttpClient.java` | Builds k-NN query after `EmbeddingProvider.embed`; signs with SigV4 and default credential provider. It is not `@Primary`, so it is not the selected production retriever while the lexical bean exists. | `MODERNIZE`, `NOT_ACTUALLY_IN_RUNTIME` | Make one tested vector adapter the selected path in Phase 2; use IRSA in Phase 3. |
| `infra/terraform/` and `infra/kubernetes/` | Terraform stages and backend Kustomize base/overlays exist; backend image is a placeholder/tag, not an ArgoCD-tracked digest. | `MODERNIZE` | Retain existing topology; add AOSS and GitOps only in later phases. |
| `.github/workflows/backend-image-publish.yml` | Builds/pushes with GitHub OIDC and resolves a digest, but does not update a Git manifest. | `MODERNIZE` | Phase 4 commits an immutable digest update and lets ArgoCD reconcile it. |
| `.github/workflows/frontend-delivery.yml` | Separate frontend delivery workflow exists; it is not Backend ArgoCD GitOps. | `REUSE_AS_IS` | Keep its scope separate. |

No managed corpus or ingestion path exists in the current repository. Consequently, no current runtime can claim live top-K vector retrieval evidence.

## 9. Classification matrix

The five labels are applied consistently above: `REUSE_AS_IS` preserves a verified boundary; `REUSE_CONCEPT_ONLY` preserves intent but not implementation; `MODERNIZE` changes an implementation to meet the target; `REMOVE` forbids a legacy pattern; `NOT_ACTUALLY_IN_RUNTIME` denies runtime status without an active path. Each row identifies repository, requested/inspected commit, exact path, observed behavior, and connection evidence; unavailable external evidence is marked rather than inferred.

## 10. Current-to-target gap matrix

| Required target | Current state | Gap / owning phase |
|---|---|---|
| Backend-owned RAG context | Prompt receives references. | Make the selected retriever vector-based and mode-governed: Phase 2. |
| Bedrock embedding → OpenSearch k-NN | Components exist but lexical bean is primary. | One selected tested vector path: Phase 2. |
| AOSS collection/index/corpus | No current AOSS infrastructure, managed corpus, or ingestion. | Collection/policies/IRSA/index/ingestion/live retrieval: Phase 3. |
| Immutable digest GitOps | Publish resolves digest but does not update manifest. | Digest commit, Application tracking, sync and verification: Phase 4. |
| ArgoCD sync/self-heal/rollback | No current ArgoCD Application. | Install/Application/sync/health/digest proof/revert rollback: Phase 4. |

## 11. Accepted modernization decisions

1. Spring Boot Backend continues to own the analysis lifecycle; Python is never the default runtime.
2. Preserve the `ReferenceRetriever` to Bedrock prompt connection.
3. Treat lexical OpenSearch as incomplete, not vector RAG.
4. Use Bedrock embedding plus OpenSearch k-NN, AOSS SigV4, IRSA, curated corpus, and safe metadata-only logs.
5. Reuse AOSS topology and Argo automated-sync/prune/selfHeal concepts, not unsafe implementation details.

## 12. Explicitly rejected legacy patterns

Rejected: static access keys; System-property credential copying; TLS hostname bypass; hard-coded accounts, roles, endpoints, or images; public AOSS/Argo ingress; `--insecure`; GitHub PAT; static AWS credential Secrets; Terraform auto-approve; direct `kubectl` mutation as deployment; and logging prompts, embedding vectors, retrieved document text, whole OpenSearch responses, Terraform text, or Secrets.

## 13. Phase 2 Backend-owned RAG boundary

Phase 2 owns retrieval-query construction, Bedrock embedding, a single vector-retrieval adapter, generation-context integration, unit/integration tests, and safe observability metadata. It reuses the existing `AnalysisJob` lifecycle, S3 source/result flow, `ReferenceRetriever` port, Bedrock prompt builder, k-NN query builder, response parser, and SigV4 client; it does not introduce a second adapter, Python service, UI, workflow, or deployment structure.

`AnalysisMode` continues to describe analysis ownership. Phase 2 adds a distinct `RagMode`/`RetrievalMode`, rather than conflating the two:

| Mode | Required behavior |
|---|---|
| `REQUIRED` | embedding or retrieval failure fails the analysis job; use for the live E2E contract. |
| `OPTIONAL` | generation can continue without references after a retrieval failure; record only failure class, latency, hit count, and document IDs when available. |
| `DISABLED` | do not invoke embedding or OpenSearch; use for local and limited verification. |

Completion requires tests proving that only the vector retriever is selected, the embedding reaches the k-NN request, retrieved documents reach the Bedrock prompt, all three modes behave as specified, and prompt/vector/retrieved-document/Terraform content is absent from logs. This phase does not provision AOSS, ingest a corpus, install ArgoCD, or run live AWS E2E.

## 14. Phase 3 AOSS and corpus boundary

Phase 3 owns Terraform AOSS encryption/network/data policies, Backend IRSA, vector index/mapping/dimension, curated corpus and idempotent ingestion, live top-K retrieval, REQUIRED browser E2E, cost control, and cleanup. It does not implement GitOps reconciliation.

The corpus is project-owned and versioned/provenanced. It is limited to Terraformers-relevant patterns such as VPC/subnets, ALB/target groups, EKS/node groups, RDS subnet/security groups, S3/CloudFront, SQS, OpenSearch, IAM/IRSA, security-group relationships, tags, and outputs. Each document has a stable ID, title, supported services, architecture pattern, Terraform guidance, security considerations, and source version. It contains no credentials, account identifiers, endpoints, state, or user uploads. Phase 3 evidence includes collection/index creation, dimension/mapping compatibility, static-key absence, IRSA signed request, corpus checksum/version/document count, top-K IDs for representative queries, saved retrieved-document IDs, context-supported generated output, REQUIRED failure behavior, and cleanup/cost records.

## 15. Phase 4 GitOps boundary

Phase 4 owns ArgoCD installation and version pinning, private/authenticated operational access, the Backend Application pointing to this repository/revision/manifest path, automated sync/prune/selfHeal, image-publish immutable digest update, concurrency and self-trigger loop protection, least-privilege Git change authority, Synced/Healthy evidence, runtime digest equality, browser smoke, Git-revert rollback, and self-heal. It does not use direct `kubectl` mutation as the release mechanism.

The required release chain is GitHub Actions build → GitHub OIDC ECR login → immutable ECR digest resolution → approved Git manifest digest update → ArgoCD reconciliation → EKS rollout. The workflow must not use `kubectl set image` or `kubectl apply` to deploy the Backend. Completion requires the same digest in ECR, Git, Deployment, and Pod image ID; ArgoCD `Synced` and `Healthy`; CloudFront browser smoke; a Git revert to the prior digest; and a deliberate drift corrected by self-heal.

## 16. Cost, security, and cleanup considerations

AOSS capacity, Bedrock invocations, EKS nodes, ECR images, S3/CloudFront delivery, and data ingestion must have explicit environment-scoped cost and cleanup evidence. Least-privilege IRSA and OIDC replace long-lived credentials. Store no secrets in manifests, Git history, logs, or evidence. Collect only request IDs, mode, status, latency, hit count, index alias/version, and digest-safe metadata.

## 17. Evidence still required before project completion

Completion needs: exact-source reinspection of the three unavailable commits; embedding dimension/index mapping proof; curated corpus and ingestion provenance; live signed AOSS top-K retrieval with context reflected in generation; IRSA/access-policy/network proof; Terraform evidence; ECR digest-to-Git manifest commit; ArgoCD Synced/Healthy and self-heal evidence; runtime image digest equality; browser smoke; and a demonstrated Git-revert rollback.

Evidence records must distinguish `source merged`, `image published`, `manifest updated`, `ArgoCD synced`, `workload healthy`, `runtime digest matched`, `browser E2E passed`, `rollback passed`, and `self-heal passed`. They may contain commit SHA, workflow run ID, ECR repository/digest, ArgoCD status, Deployment generation, Pod image ID, analysis job ID, retrieval mode/hit count/document ID, corpus version, latency, and success/failure state. They must not contain access keys, tokens, passwords, kubeconfig, raw tfvars, tfstate, Terraform plan JSON, embeddings, prompts, retrieved text, generated Terraform text, or user-upload originals.

## 18. Out of scope for this PR

No Backend/Frontend/Python code, Terraform, Kubernetes/Helm manifest, GitHub Actions, script, dependency, secret, AWS resource, Terraform operation, kubectl/helm mutation, deployment, merge, or PR-time runtime change is made here. This PR changes only this inventory document.
