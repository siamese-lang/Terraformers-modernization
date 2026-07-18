# Terraformers Modernization Completion Plan

## Final objective

Modernize the original Terraformers team service without replacing its core purpose.

The completed service must:

1. authenticate users through Cognito;
2. accept an architecture image;
3. create a durable asynchronous analysis job;
4. generate a non-placeholder Terraform draft through Bedrock;
5. improve generation quality with embedding and OpenSearch-based retrieval;
6. persist source and result artifacts in S3 and the canonical RDB domain;
7. let owners inspect and publish their projects;
8. let guests inspect public projects and authenticated users write comments;
9. deploy through guarded OIDC workflows; and
10. demonstrate monitoring, retry, failover, and recovery behavior.

## Reuse policy

Use the current modernization repository as the canonical implementation.

Reuse from the current repository:

- Cognito and JWT integration
- RDB user, project, file, collaboration, and analysis-job domains
- Flyway migrations
- S3 source and result persistence
- upload and analysis polling contracts
- project-tree APIs
- public-project and comment APIs
- EKS, RDS, CloudFront, and deployment infrastructure

Reuse selectively from the original repository:

- generate, personal-project, and public-project screen responsibilities
- image-analysis prompt structure
- embedding and OpenSearch retrieval flow
- analysis progress presentation
- SQS polling and asynchronous-processing concepts

Do not restore:

- DynamoDB as the canonical domain store
- browser-provided AWS access keys
- Terraform apply, destroy, or tfstate operations in the UI
- static AWS credentials
- disabled TLS verification
- the monolithic original AiChat component

## Delivery phases

| Phase | Scope | Status |
| --- | --- | --- |
| 0 | Completion plan and verified baseline | Complete |
| 1 | Application shell, routes, authentication boundary, logout | In progress |
| 2 | Personal and public project UX and canonical API contracts | Pending |
| 3 | Real Bedrock multimodal analysis and Terraform quality gate | Pending |
| 4 | Embedding and OpenSearch RAG | Pending |
| 5 | SQS analysis worker, retries, idempotency, and DLQ | Pending |
| 6 | Backend and frontend OIDC delivery automation | Pending |
| 7 | High availability, observability, and recovery scenarios | Pending |
| 8 | Final browser E2E and portfolio evidence | Pending |

## Verified baseline

Completed:

- Cognito sign-up, confirmation, and sign-in
- CloudFront same-origin API delivery
- upload of the previously failing 1,440,971-byte image with HTTP 201
- source-object persistence
- project and analysis-job creation
- analysis polling and project-tree persistence

Known incomplete behavior:

- the current analysis provider is a stub
- provider-only Terraform output can be marked successful
- the sidebar is not interactive
- unrelated generate, project, community, and comment panels share one screen
- no account menu or user-initiated logout exists
- routed application shell implemented
- auth/navigation tests implemented
- live browser E2E pending
- frontend OIDC deployment repair pending

## Current implementation boundary

Phase 1 reorganizes and reuses existing frontend behavior. It does not change:

- Bedrock
- OpenSearch
- embedding
- SQS
- backend persistence
- Kubernetes runtime
- Terraform-managed infrastructure

## Phase 1 exit criteria

- real navigation for Generate, My Projects, and Community
- URL and selected menu remain consistent
- authenticated user identity is visible
- user-initiated logout works
- Generate and My Projects require authentication
- Community remains available to guests
- Generate does not render community comments or project inspectors
- private project identifiers are not sent to public comment APIs
