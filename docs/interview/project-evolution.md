# Terraformers project evolution

This note separates the 2024 team-project evidence from the currently enabled modernization runtime. It is an interview aid, not a claim that every historical component is live today.

## Repository comparison and reuse boundary

The modernization keeps the owner-rooted `project` / `project_file` / `analysis_job` model, private-object storage, Cognito identity mapping, common project-access checks, and asynchronous provider boundary. These are the parts that can be reused directly from the RDB refactoring direction. The browser flow is deliberately improved around persistent job state rather than restoring the former large chat/upload controller designs.

The original repositories remain the evidence source for the 2024 OpenSearch RAG document contract and GitHub Actions/ArgoCD deployment design. They are not copied wholesale: user-managed AWS credentials, browser-visible queue URLs, Terraform apply/destroy controls, and non-persistent `CompletableFuture` analysis execution are not part of this modernization.

## A. 2024 team project

The 2024 team project converted AWS architecture images into Terraform with Bedrock and OpenSearch-backed RAG. Its deployment architecture used an EKS backend, S3 and CloudFront web delivery, Terraform-managed infrastructure, and GitHub Actions plus ArgoCD GitOps. Those facts describe the team system and collaboration evidence; this document does not attribute every component to one individual.

The original OpenSearch retrieval/index/mapping and ArgoCD Terraform/Application/workflow material should remain referenceable as historical evidence. They must not be removed merely because a cost-controlled modernization environment does not activate them.

## B. Current modernization

The active code path uses Cognito authentication, the relational project aggregate (`project`, `project_file`, `analysis_job`), private S3 object access through the backend, persistent analysis jobs, EKS/IRSA-oriented runtime configuration, an internal ALB with CloudFront as the public entry design, Terraform infrastructure, and the repository's GitHub Actions workflows.

`BedrockAnalysisProvider` still retrieves references through `ReferenceRetriever` before it constructs the Bedrock prompt. The OpenSearch retriever, embedding-model settings, endpoint/index/vector/content-field settings, and no-reference fallback are retained behind configuration. OpenSearch is intentionally optional and no live index deployment or ingestion is performed by this change.

The current browser flow always creates a new private project from one image, returns an analysis job immediately, and reconstructs status/results from the backend project detail. The latest job is the binding for both its source image and result Terraform file.

## C. Replacement and operating boundary

The modernization replaces chat-local transient results and upload-modal polling with the `/projects/:projectId` detail route and persisted `AnalysisJob` polling. It replaces public object assumptions with private S3/backend reads and reinforces owner/admin/public authorization through domain services.

ArgoCD is not represented as a live modernization deployment path unless a separately verified environment says so. The current workflow/deployment boundary may use repository-integrated verification or direct deployment practices because of repository consolidation, temporary live validation, and cost controls; that is distinct from the 2024 GitOps pipeline.

## Remaining limitations

This work does not add worker-restart recovery, revision/history UI, quotas or idempotency, detailed progress stages, live OpenSearch provisioning/index ingestion, or an ArgoCD sync. These are intentional scope boundaries, not live capabilities.
