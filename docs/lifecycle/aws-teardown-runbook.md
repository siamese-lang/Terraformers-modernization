# AWS Teardown Runbook

## 1. Purpose and safety boundary

This runbook removes every AWS resource attributable to Terraformers-modernization while preserving enough bootstrap access to finish and verify the teardown.

It is not a single `terraform destroy` command. The environment contains:

- seven remote Terraform states;
- GitOps and Kubernetes resources;
- controller-generated AWS load-balancer resources;
- mutable data and object versions;
- service-generated logs and traces;
- manually initialized values and test users;
- GitHub configuration outside AWS.

Deletion is performed in two phases:

1. **Runtime teardown** — remove service, data, EKS, RAG, delivery, stateful, runtime, and network resources while keeping the state bucket, GitHub OIDC provider, and final teardown role.
2. **Bootstrap teardown** — remove state, OIDC, and foundation roles only after the residual scan proves that no runtime resource remains.

No command in this document is approval to mutate AWS. Each destructive execution requires an explicit user decision after reviewing the inventory, data-loss decisions, and destroy plan.

## Current execution record (not an instruction)

Runtime teardown is already complete. Read-only runtime closure workflow run `29904386655` passed: all six runtime Terraform states have zero managed instances and all exact active runtime AWS counts are zero. Active runtime Secret count is 0; one Secret remains as a pending-deletion tombstone. This runbook remains a deletion **design**; the execution record is [aws-runtime-teardown-closure.md](aws-runtime-teardown-closure.md) and the current gate is [closure-progress.md](closure-progress.md).

Bootstrap inventory passed with 16 managed resources and 9 data sources. The versioned remote-state bucket has 231 object versions, 159 delete markers, 8 current objects, 0 multipart uploads, and 318 lock-object versions; MFA Delete and Object Lock are absent and S3 access-point count is 0. The project GitHub OIDC provider is trusted by `terraformers-live-teardown`, `terraformers-live-terraform-apply`, and `terraformers-live-terraform-plan`. An independent administrator/CloudShell identity is mandatory for final removal.

Extra final-pass inventory is still required for `terraformers-modernization-live-smoke-backend-irsa-role` and its `terraformers-modernization-live-smoke-backend-runtime-access` policy, the `v1` non-default version of `terraformers-live-apply-operations-visibility-create` (default `v2`), and possible EKS OIDC-provider residue. Bootstrap deletion is not approved or executed, and zero-resource proof is not complete.

## 2. Preconditions

Do not begin destroy planning until all of the following are true:

- `docs/lifecycle/aws-resource-inventory.md` contains the completed live inventory;
- final portfolio evidence has been frozen;
- no Backend image, frontend delivery, corpus ingestion, Terraform apply, or Argo CD change is in progress;
- the integration commit and AWS account are recorded;
- every versioned S3 bucket, RDS snapshot, Secret, AOSS corpus/index, ECR repository, and CloudWatch log group has an explicit retention decision;
- the exact GitHub environment and OIDC role that will finish the teardown are known;
- the bootstrap state bucket is not included in the first runtime destroy phase.

## 3. Mandatory data-loss decisions

Record one decision for each row before generating a destroy plan.

| Data area | Available decision | Closure default | Redeployment consequence |
|---|---|---|---|
| RDS | final snapshot temporarily retained / no final snapshot | no final snapshot after evidence is complete | database starts empty; Flyway recreates schema |
| Existing RDS snapshots | retain outside project / delete | delete for zero-resource proof | no data restore path remains |
| Upload/result S3 objects and versions | export selected evidence / delete all versions | retain only sanitized portfolio evidence outside project buckets, then delete all | sample projects and results must be recreated |
| Frontend bucket objects | delete all versions | delete | workflow rebuilds and resyncs |
| RAG corpus package/receipt bucket objects | retain committed corpus only / export receipt / delete versions | corpus stays in Git; sanitized receipt may be retained outside AWS | ingestion reruns from committed corpus v2 |
| AOSS index/documents | delete | delete | ingestion recreates index/documents |
| ECR images | retain external digest record / delete images | retain digest string in evidence, delete repository contents | image must be rebuilt and republished |
| Secrets Manager values | recovery-window deletion / force deletion | decide based on redeploy timing; never export values | scheduled deletion can block same-name redeploy |
| Cognito users | delete with pool | delete | test user must be recreated |
| CloudWatch logs and X-Ray traces | retain for bounded period / delete | retain only screenshots or sanitized identifiers needed for portfolio, then delete AWS resources | no console history after teardown |
| Terraform state | export encrypted copy / delete all versions | export only if explicitly approved; otherwise delete after zero-runtime proof | redeploy begins from a new bootstrap |

A retained AWS snapshot, log group, bucket, object version, or Secret is still an AWS resource. It must be included in the final residual result or explicitly excluded from the goal. The default closure goal is zero project resources.

## 4. Destroy-plan rules

Generate a separate destroy plan for each state component. Do not produce one cross-state plan.

Each plan review must record:

- integration commit;
- expected AWS account and region;
- state component;
- number of delete actions;
- any read actions;
- create, update, replacement, or import action count;
- high-cost resources being removed;
- external prerequisites;
- data cleanup required before apply;
- resources expected to remain because they belong to a later state.

A destroy plan is rejected when:

- it creates or replaces a resource;
- it updates an unrelated resource to make destroy succeed;
- it attempts to delete the state bucket or execution role before other states;
- an ALB, ENI, VPC endpoint, bucket object version, image, snapshot, or scheduled Secret exists without a cleanup owner;
- the resource list does not match the completed inventory;
- the plan depends on uncommitted tfvars or local state.

Saved destroy plans can contain sensitive values. They remain inside the approved GitHub Actions job and are never uploaded as artifacts.

## 5. Phase 0 - Freeze the operating environment

1. Record the final integration commit and deployed Backend digest.
2. Stop or disable scheduled/dispatch delivery workflows for the teardown window.
3. Confirm that no Terraform apply, image publish, frontend delivery, corpus ingestion, or Argo CD sync is running.
4. Freeze the final browser, GitOps, telemetry, and incident evidence.
5. Record the current GitHub environment/variable/secret names without values.
6. Confirm the bootstrap role and state bucket can still be accessed through GitHub OIDC.

Do not revoke OIDC, delete the state bucket, or remove the apply role in this phase.

## 6. Phase 1 - Stop public delivery and reconciliation

### 6.1 Stop Argo CD reconciliation

- disable automated sync or suspend the Backend Application;
- confirm Argo CD will not recreate a deleted Deployment, Service, ConfigMap, Ingress, or ExternalSecret;
- record the final desired revision and health state;
- do not delete Argo CD itself before the managed application resources are removed.

### 6.2 Stop CloudFront delivery

- freeze frontend deployment and invalidation workflows;
- record the distribution and VPC-origin ownership from Terraform state;
- disable or destroy the CloudFront distribution through the reviewed `frontend-delivery` plan as required by AWS deletion semantics;
- confirm CloudFront no longer references the internal ALB before deleting the Ingress.

### 6.3 Stop application traffic and asynchronous work

- confirm no analysis job is RUNNING;
- stop new browser analysis submissions;
- confirm no corpus ingestion CodeBuild run is active;
- confirm no SQS message or retry policy requires processing before deletion.

## 7. Phase 2 - Remove Kubernetes owners before EKS

The EKS cluster is not the first deletion target.

Delete in owner order:

1. Backend Argo CD Application or its managed Backend resources.
2. Backend Ingress.
3. Wait for the AWS Load Balancer Controller to delete the internal ALB, listeners, target groups, target registrations, and generated security-group resources.
4. ExternalSecret, SecretStore, generated Kubernetes Secret, and Backend runtime resources.
5. AWS Load Balancer Controller Helm release and its Kubernetes objects.
6. External Secrets Operator Helm release and its Kubernetes objects.
7. Argo CD applications, then Argo CD Helm release.
8. Any temporary diagnostic Pods, Jobs, or namespaces.

Required checks before EKS destroy:

- no Ingress remains;
- no project LoadBalancer Service remains;
- internal ALB and target groups are absent;
- no controller finalizer is blocking deletion;
- no project PersistentVolume or LoadBalancer resource remains;
- no project namespace contains a terminating object;
- the CloudWatch add-on and managed add-ons are represented in the reviewed EKS destroy plan.

Never delete the cluster to force-remove a stuck controller-owned ALB. Resolve the owner/finalizer boundary first.

## 8. Phase 3 - Empty or prepare mutable service data

Perform only the cleanup required by the reviewed retention decisions.

### 8.1 S3

For every project bucket:

- list versioning status;
- count current objects, noncurrent versions, and delete markers;
- export only explicitly approved sanitized evidence;
- remove multipart uploads if present;
- remove all object versions and delete markers when the bucket must be deleted;
- verify zero versions before the Terraform destroy applies.

`aws s3 rm --recursive` is not sufficient for a versioned bucket.

### 8.2 ECR

- record the deployed image digest in the portfolio evidence;
- delete images when repository deletion requires it;
- verify no manifest list or untagged image remains;
- do not retain a repository merely to preserve an image that can be rebuilt.

### 8.3 RDS

- confirm no application connection remains;
- apply the approved final-snapshot decision;
- record whether deletion protection, retained automated backups, or final snapshot settings must be changed by reviewed Terraform;
- remove retained snapshots before the final zero-resource proof unless the closure scope explicitly excludes them.

### 8.4 Secrets Manager

- choose recovery-window or force deletion before Terraform destroy;
- record the redeployment impact of scheduled deletion;
- never write Secret values to logs or evidence;
- verify both active and pending-deletion project Secrets in the residual scan.

### 8.5 AOSS and corpus data

- stop ingestion;
- retain committed corpus v2 and sanitized receipt only;
- delete service-created index/documents when needed, or allow collection deletion to remove them;
- verify that no project collection, policy, endpoint, index, or CodeBuild project remains.

### 8.6 Cognito

- confirm no test token or user data is part of evidence;
- delete test users with the pool/client;
- record only the recreation procedure.

### 8.7 CloudWatch and X-Ray

- retain only approved screenshots, metric names, trace IDs, and sanitized log identifiers;
- remove Terraform-managed dashboard and alarms with the EKS state;
- explicitly remove service-generated log groups that are not in state;
- verify retention-policy leftovers do not keep project resources alive.

## 9. Phase 4 - Runtime Terraform teardown order

The exact order is confirmed by the completed inventory and destroy plans. The default reverse-dependency order is:

1. `frontend-delivery`
2. Kubernetes/controller-generated resources not in Terraform state
3. `rag-runtime`
4. `eks-runtime`
5. `stateful-dependencies`
6. `runtime-dependencies`
7. `network`

### 9.1 `frontend-delivery`

Prerequisites:

- delivery frozen;
- distribution disabled as required;
- frontend bucket versions removed if the Terraform resource cannot remove them;
- CloudFront no longer references the internal ALB.

Expected result:

- no distribution, OAC, function, VPC origin, frontend bucket, delivery role, or related policy remains.

### 9.2 `rag-runtime`

Prerequisites:

- no ingestion build running;
- Backend retrieval stopped;
- corpus bucket versions handled;
- AOSS data-retention decision completed.

Expected result:

- no AOSS collection/policy/endpoint, CodeBuild project/role, corpus bucket, RAG security group/rules, or RAG IAM resource remains.

### 9.3 `eks-runtime`

Prerequisites:

- application and operators removed;
- internal ALB and target groups absent;
- no project Ingress/LoadBalancer/PV remains;
- final telemetry evidence frozen.

Expected result:

- add-ons, dashboard, alarms, IRSA roles, node group, and cluster are removed in the Terraform dependency order;
- no EKS ENI or security group remains unmanaged.

### 9.4 `stateful-dependencies`

Prerequisites:

- Backend stopped;
- RDS and Cognito retention decisions complete;
- final snapshot settings approved.

Expected result:

- no RDS instance, DB subnet group, DB/security group, managed credential Secret, Cognito pool/client, or stateful IAM resource remains.

### 9.5 `runtime-dependencies`

Prerequisites:

- S3 versions, ECR images, SQS messages, and Secret deletion mode handled.

Expected result:

- no ECR repository, application bucket, SQS queue, runtime Secret container, or related IAM resource remains.

### 9.6 `network`

Prerequisites:

- no EKS, RDS, AOSS endpoint, ALB, VPC origin, NAT dependency, interface endpoint, or project ENI remains.

Expected result:

- no subnet, route table, gateway, NAT gateway, VPC endpoint, security group, ENI, or VPC remains.

## 10. Phase 5 - Runtime residual scan

Before bootstrap teardown, verify at minimum:

- EKS cluster/node group/add-ons: zero;
- RDS instances and project snapshots: zero;
- AOSS collections, policies, and VPC endpoints: zero;
- CloudFront distributions and VPC origins: zero;
- project S3 buckets, object versions, delete markers, and multipart uploads: zero;
- ECR repositories/images: zero;
- SQS queues: zero;
- Cognito user pools/clients: zero;
- active and pending-deletion Secrets: zero;
- project VPCs, subnets, NAT gateways, endpoints, ENIs, security groups, ALBs and target groups: zero;
- project IAM roles, policies and instance profiles except the documented bootstrap plane: zero;
- project CloudWatch dashboards, alarms, log groups and retained traces: zero unless explicitly approved;
- all runtime Terraform state components contain zero managed resource instances or have been deliberately removed.

Any residual resource returns the process to its owner phase. Do not add an ad hoc broad deletion script.

## 11. Phase 6 - Bootstrap teardown

Bootstrap resources are deleted only after the runtime residual scan passes.

Default order:

1. Export a sanitized list of state components and final serials; never export raw state unless explicitly approved and encrypted outside the project bucket.
2. Confirm all runtime state objects are no longer needed.
3. Remove GitHub Actions plan/apply role attachments and roles while preserving one final authorized identity until the state bucket and OIDC deletion path is ready.
4. Delete the GitHub OIDC provider only when no remaining GitHub Actions job requires it and it is confirmed to be project-specific rather than shared.
5. Delete all object versions, delete markers, and lock objects from the Terraform state bucket.
6. Delete the state bucket.
7. Remove the final bootstrap role/policy with the independent administrator or CloudShell identity used for bootstrap closure.

A role cannot delete itself after its credentials are gone. The final action must be executed from an identity outside the project bootstrap plane.

## 12. Final zero-resource proof

The teardown is complete only when the residual summary records:

```text
runtime_resources_remaining=0
bootstrap_resources_remaining=0
project_s3_object_versions_remaining=0
project_snapshots_remaining=0
project_secrets_active_or_pending_deletion=0
project_iam_roles_and_policies_remaining=0
project_network_resources_remaining=0
project_observability_resources_remaining=0
aws_teardown_result=PASS
```

The summary must also record:

- account and region verified;
- integration commit used for the inventory and runbooks;
- date of runtime teardown;
- date of bootstrap teardown;
- GitHub configuration retained or removed;
- any explicitly accepted non-project shared resource.

## 13. Failure and restart rules

- Stop at the first actual failing dependency.
- Record the resource owner and AWS error once.
- Re-run only the failed phase after correcting the owner or retention decision.
- Do not rerun completed destroy phases merely for reassurance.
- Do not edit Terraform state, import, or force-delete a controller-owned resource without evidence that the normal owner path cannot complete.
- Do not widen IAM permissions broadly to make teardown easier.
- Keep the bootstrap plane until all runtime deletion and residual checks are complete.

## 14. Completion handoff

When a teardown conversation is restarted, continue from the last completed phase in this file and the populated inventory. Do not infer state from old command output. Re-read only the current inventory, the latest destroy-plan summaries, and the last residual result.