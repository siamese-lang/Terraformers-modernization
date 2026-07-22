# AWS Redeployment Runbook

## 1. Purpose

This runbook recreates Terraformers-modernization after a complete AWS teardown without depending on the current local Windows disk for Terraform execution.

The canonical model is:

```text
Independent AWS administrator or AWS CloudShell
  -> minimal bootstrap
     - Terraform state bucket
     - GitHub OIDC provider
     - plan/apply roles
  -> GitHub Actions
     - remote-state Terraform stages
     - immutable image publication
     - frontend delivery
     - RAG ingestion
  -> approved operator steps
     - Kubernetes controllers
     - External Secrets
     - Argo CD and Backend Application
     - test user and final acceptance
```

The local machine is an operator console for `git`, `gh`, `aws`, and `kubectl`; it is not the required Terraform runtime.

## 2. Redeployment paths and present boundary

This runbook documents recovery; it does **not** prove a redeployment was performed. The AWS runtime has been torn down and independently verified, bootstrap inventory passed, and bootstrap deletion/full zero-resource proof remain pending.

### Retained-bootstrap redeployment

Use this only when the state bucket, GitHub OIDC provider, and required plan/apply roles were deliberately retained. Reconfirm their exact state, trust, versioned objects, and GitHub configuration before resuming at `network`. This is no longer the selected closure outcome.

### Full-zero-state redeployment

The selected `DELETE_BOOTSTRAP_FOR_ZERO_RESOURCE_PROOF` path requires, after deletion and a truthful zero-resource result:

1. independent administrator or CloudShell identity;
2. state-bucket recreation;
3. GitHub Actions OIDC provider creation or explicitly documented compatible-provider reuse;
4. Terraform plan/apply roles and exact trust recreation;
5. GitHub Environment, variable, and encrypted-tfvars restoration;
6. bootstrap state migration to the remote backend;
7. `network`;
8. `runtime-dependencies`;
9. `stateful-dependencies`;
10. `eks-runtime`;
11. `rag-runtime`;
12. `frontend-delivery`;
13. External Secrets and AWS Load Balancer Controller;
14. immutable Backend image publish;
15. Argo CD desired-state update;
16. RAG corpus ingestion; and
17. browser/API/RDB/S3/GitOps/telemetry acceptance.

A pending Secret deletion can block same-name recreation. Global S3 names can also collide; check both before bootstrap. Exact environment and secret names must be read from current workflow source, not guessed.

## 3. Redeployment principles

- Reuse the existing Terraform roots, workflows, manifests, chart versions, scripts, and committed corpus.
- Do not recreate resources manually in the AWS Console when a Terraform or GitOps owner exists.
- Do not use static AWS access keys in GitHub.
- Do not upload raw tfvars, tfstate, kubeconfig, Secret values, prompts, source images, retrieved text, or generated Terraform as workflow evidence.
- Apply one state component at a time in the documented order.
- Review each live plan before apply.
- Do not combine bootstrap, network, EKS, RAG, and application deployment into one workflow or script.
- Do not restore deprecated Python analysis or old public exposure paths.
- Do not treat a successful resource creation as service acceptance. Complete browser, runtime, GitOps, and observability checks.

## 4. Inputs that must exist outside the repository

Record names and sources, never values.

### 3.1 AWS account inputs

- target AWS account ID;
- region, normally `ap-northeast-2`;
- independent administrator or CloudShell identity for bootstrap;
- globally unique S3 bucket names;
- project/environment naming values;
- approved Bedrock model or inference profile identifiers;
- required existing account-level service access decisions.

### 3.2 GitHub environments

At minimum preserve or recreate:

- `aws-live-plan`;
- `aws-live-apply`;
- `frontend-delivery`;
- any environment used by immutable image publication or corpus ingestion.

Approval rules remain separate from workflow code.

### 3.3 GitHub variables

Expected names include:

- `AWS_REGION`;
- `AWS_ROLE_TO_ASSUME` for the environment-specific plan/apply role;
- `AWS_TERRAFORM_STATE_BUCKET`;
- `AWS_TERRAFORM_STATE_PREFIX`;
- frontend delivery role/bucket/distribution variables already used by the existing workflow;
- expected account and project-specific non-secret identifiers already defined by current workflows.

Confirm exact names from workflow source before recreation. Do not invent aliases.

### 3.4 GitHub encrypted secrets

Expected Terraform tfvars secret names:

- `AWS_LIVE_FOUNDATION_TFVARS_B64`;
- `AWS_LIVE_NETWORK_TFVARS_B64`;
- `AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64`;
- `AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64`;
- `AWS_LIVE_EKS_TFVARS_B64`;
- `AWS_LIVE_FRONTEND_TFVARS_B64`;
- `AWS_LIVE_RAG_TFVARS_B64`.

Additional delivery or runtime initialization secrets must be read from the existing workflows. Values are generated from approved private inputs and never committed.

## 5. Stage 0 - Pre-bootstrap checks

Before creating any resource:

1. Verify the target account and region.
2. Confirm no previous project resource, pending Secret deletion, retained snapshot, state bucket, OIDC provider, role, bucket name, or log group conflicts with the new deployment.
3. Confirm GitHub integration branch and release source.
4. Confirm the Terraform roots pass static verification.
5. Confirm private tfvars can be regenerated from documented inputs.
6. Confirm the desired bucket names are available.
7. Confirm whether the account already has a reusable GitHub OIDC provider. Reuse only when the trust boundary and ownership are documented.
8. Confirm the deployment cost boundary, especially NAT gateways, EKS nodes, RDS, AOSS, CloudWatch, and Bedrock usage.

Do not begin bootstrap while a prior deletion is still pending under the same resource name.

## 6. Stage 1 - Independent bootstrap

A complete teardown removes the state bucket and GitHub OIDC role, so GitHub Actions cannot bootstrap itself.

Use an independent AWS administrator session or AWS CloudShell for this stage only.

### 5.1 Bootstrap responsibilities

The minimal bootstrap must create or adopt:

- Terraform remote-state S3 bucket with versioning, encryption, public-access blocking, and native lockfile support;
- GitHub OIDC provider when a compatible shared provider does not exist;
- Terraform live-plan role;
- Terraform live-apply role;
- exact GitHub trust subjects and environment boundaries;
- minimum permissions required to plan and apply the reviewed Terraform roots.

### 5.2 Bootstrap execution model

Use the existing root:

```text
infra/terraform/bootstrap/aws-live-foundation
```

The bootstrap procedure must be verified against the current source before execution because the root may itself manage the state bucket and roles.

The intended pattern is:

1. run the foundation root in AWS CloudShell with a temporary local backend or an explicitly documented pre-state bootstrap mode;
2. create the versioned state bucket and OIDC roles;
3. move or reinitialize the foundation state into the new S3 backend;
4. verify the state object and lock behavior;
5. configure GitHub environment variables and encrypted tfvars;
6. stop using the independent administrator for normal Terraform stages.

Do not create a second foundation implementation unless the existing root cannot bootstrap from zero. Any required bootstrap exception must remain minimal and documented in this section.

### 5.3 Bootstrap acceptance

- AWS identity and account match;
- state bucket exists, is private, encrypted, and versioned;
- GitHub OIDC trust is limited to the repository and intended environments;
- plan and apply roles are distinct where the current design requires it;
- GitHub Actions can read the state backend through OIDC;
- no static credentials are stored.

## 7. Stage 2 - GitHub configuration restoration

1. Recreate required GitHub environments and approval rules.
2. Set non-secret variables.
3. Generate stage tfvars from approved private inputs.
4. Base64-encode and store each stage tfvars in the existing encrypted secret name.
5. Verify the workflow references resolve to exactly one variable/secret owner.
6. Run the execution-plan contract with no AWS mutation.
7. Run the Terraform state inventory and confirm only bootstrap resources exist.

Do not print decoded tfvars or secret values in workflow logs.

## 8. Stage 3 - Terraform deployment order

The canonical order is:

1. `bootstrap`
2. `network`
3. `runtime-dependencies`
4. `stateful-dependencies`
5. `eks-runtime`
6. `rag-runtime`
7. `frontend-delivery`

The exact dependency graph is confirmed by the current Terraform outputs and plan workflow.

For each stage:

1. dispatch a live plan from the exact integration commit;
2. verify expected account, region, state key, and private tfvars source;
3. review the sanitized risk summary;
4. reject unintended update, delete, replacement, public exposure, optional adapter, or high-cost change;
5. execute the existing approved apply contract or the closure-approved stage apply mechanism;
6. run one post-apply plan and confirm no unexplained diff;
7. record the state component and output transfer path without publishing sensitive outputs;
8. continue only after the stage acceptance is complete.

### 7.1 Network

Expected outcome:

- VPC, public/private subnets, routes, NAT/IGW and required endpoints exist;
- subnet/AZ placement matches EKS, RDS, AOSS, and CloudFront VPC-origin requirements;
- no unintended public Backend path exists.

### 7.2 Runtime dependencies

Expected outcome:

- ECR, application S3 buckets, SQS, runtime Secret containers, and related IAM exist;
- buckets are private and versioning/lifecycle behavior matches the source;
- ECR is empty until immutable image publication;
- Secret containers exist without exposing values.

### 7.3 Stateful dependencies

Expected outcome:

- RDS, subnet/security boundaries, Cognito pool/client, and managed database credential path exist;
- Flyway-compatible database endpoint and managed password pointer can be supplied to runtime initialization;
- test users are not created in Terraform unless current source explicitly owns them.

### 7.4 EKS runtime

Expected outcome:

- cluster and managed node group are Active;
- node desired/min/max remain the documented values unless separately approved;
- IRSA roles and managed add-ons exist;
- CloudWatch observability resources match the current source;
- cluster access is available to the operator and controller roles;
- no application is deployed yet merely because the cluster exists.

### 7.5 RAG runtime

Expected outcome:

- private AOSS collection, policies and endpoint exist;
- private CodeBuild ingestion executor and exact dispatcher permissions exist;
- corpus bucket/prefix and IAM boundaries match the existing ingestion workflow;
- EKS-to-AOSS and CodeBuild-to-AOSS network paths are private;
- no public AOSS endpoint is introduced.

### 7.6 Frontend delivery

Create only after the internal origin path can be established.

Expected outcome:

- private frontend S3 bucket and OAC exist;
- CloudFront distribution, function, cache behaviors and VPC origin match source;
- the `/api/*` path points only to the internal ALB origin;
- static and API caching behavior matches the current design;
- no public S3 or direct public Backend origin exists.

## 9. Stage 4 - Kubernetes platform bootstrap

Terraform creates AWS infrastructure; it does not complete every in-cluster owner.

Install or apply in this order, using pinned source versions and current manifests:

1. External Secrets Operator CRDs and Helm release.
2. External Secrets IRSA ServiceAccount and runtime namespace prerequisites.
3. SecretStore and ExternalSecret mapping.
4. AWS Load Balancer Controller ServiceAccount/IRSA and pinned chart.
5. Argo CD pinned non-HA chart and values.
6. Argo CD Backend Application only after a real immutable ECR digest is committed.

For each operator:

- render or template before apply;
- confirm namespace, ServiceAccount, IRSA annotation, chart version, resource requests, and public exposure;
- apply once;
- wait for Ready/Established state;
- record the owner and rollback command;
- do not add a second operator or install path for convenience.

## 10. Stage 5 - Runtime Secret initialization

The Backend runtime Secret is assembled from Terraform outputs and the RDS managed password pointer through the existing External Secrets contract.

Required principles:

- do not copy the database password into GitHub inputs or repository manifests;
- initialize only non-password runtime values in the approved Secret container;
- keep the RDS managed password in its AWS-managed Secret;
- verify SecretStore and ExternalSecret Ready status;
- verify the generated Kubernetes Secret contains the required key names without printing values;
- rotate or recreate values through the owning AWS Secret, not by editing the generated Kubernetes Secret.

## 11. Stage 6 - Immutable Backend delivery

1. Run Backend verification from the integration commit.
2. Publish an immutable image with the existing GitHub OIDC workflow.
3. Resolve and record the ECR digest.
4. Create or merge the digest-only GitOps manifest update.
5. Allow Argo CD to reconcile.
6. Verify:
   - Argo CD `Synced` and `Healthy`;
   - Git digest, Deployment image and Pod image ID match;
   - Backend probes pass;
   - source revision is present;
   - the Pod security context retains non-root UID `10001` and RuntimeDefault seccomp;
   - Java auto-instrumentation state matches the current observability design;
   - no direct `kubectl set image` or mutable tag was used.

Rollback is a Git revert to the previous digest followed by Argo CD reconciliation.

## 12. Stage 7 - Internal origin and frontend delivery

1. Apply the canonical internal Backend Ingress.
2. Wait for the AWS Load Balancer Controller to create the internal ALB and healthy target group.
3. Confirm security-group boundaries and no public ALB exposure.
4. Confirm CloudFront VPC origin references the internal ALB.
5. Build the frontend with current Cognito public identifiers and same-origin API configuration.
6. Sync to the private frontend bucket through the existing OIDC delivery workflow.
7. Invalidate CloudFront as defined by the workflow.
8. Run browser login, upload, analysis, project result, and Terraform draft smoke tests.

## 13. Stage 8 - RAG corpus ingestion

1. Validate the committed corpus v2 contract.
2. Package the corpus and ingestion utility through the existing workflow.
3. Upload only to the approved corpus prefix.
4. Start the exact private CodeBuild project.
5. Wait for bounded completion.
6. Verify document count, metadata version, representative k-NN query, and sanitized receipt.
7. Keep the Backend runtime fixed to the approved corpus/provider version.
8. Do not create a new collection or index merely to repeat validation.

Corpus source remains in Git; the vector index is reproducible data.

## 14. Stage 9 - Final service acceptance

Complete one bounded acceptance pass:

- CloudFront is the only public entry;
- login and Cognito flow succeed;
- upload and asynchronous analysis complete;
- RDB metadata and S3 source/result objects align;
- Bedrock facts, AOSS retrieval and Terraform draft generation complete;
- Argo CD is Synced/Healthy and runtime digest matches Git;
- Backend health and probes pass;
- CloudWatch logs and Container Insights arrive;
- Application Signals and X-Ray state are explicitly recorded as success or limitation;
- custom analysis/Bedrock/AOSS metrics use bounded dimensions;
- no Secret, prompt, source image, retrieved text, or generated Terraform is exposed in evidence.

Do not claim automatic deployability of the generated Terraform, autoscaling, application high availability, or multi-region recovery unless separately implemented and proven.

## 15. Failure and restart points

When a stage fails:

1. stop at the first failing boundary;
2. record the exact state component, resource owner, and error;
3. inspect current remote state before changing code;
4. prefer recovery from the same state over deletion/import/recreation;
5. fix the narrow owner or permission mismatch;
6. rerun only the failed stage;
7. run one post-recovery no-diff plan;
8. update the incident record when the failure teaches a reusable engineering decision.

Do not create a new recovery workflow for every partial apply. Reuse state-aware contracts and current plan/apply mechanisms.

## 16. Redeployment completion criteria

Redeployment is complete only when:

- all seven Terraform state components are healthy and have no unexplained drift;
- all required operators are Ready;
- Argo CD reconciles the immutable Backend digest;
- runtime Secrets are delivered without exposing values;
- the internal ALB and CloudFront VPC origin are healthy;
- frontend and Backend delivery workflows succeed;
- corpus v2 is ingested and selected;
- one browser analysis succeeds;
- final telemetry state is recorded;
- the resource inventory is regenerated for the new deployment;
- teardown and redeploy procedures still match the actual owners.

## 17. New-conversation handoff

A restarted redeployment conversation must read:

1. `docs/current-operations-delivery-plan.md`;
2. this runbook;
3. the latest populated `aws-resource-inventory.md`;
4. the latest successful stage and plan/apply summary.

Resume from the first incomplete stage. Do not repeat completed stages or redesign the architecture.