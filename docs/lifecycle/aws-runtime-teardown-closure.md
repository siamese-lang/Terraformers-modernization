# AWS Runtime Teardown Closure

Status: runtime deletion completed; one read-only closure verification remains before any bootstrap decision

Source integration commit after the network recovery merge: `3162bdcb6dc02ab41fb958ca2837dc78b8c5b3c1`

## 1. Closure boundary

This record closes only the Terraformers runtime plane.

The following bootstrap resources are intentionally outside this closure:

- Terraform state bucket and its object versions;
- GitHub Actions OIDC provider;
- foundation, plan, apply, and final teardown identities and policies;
- GitHub repository and Environment configuration.

No bootstrap resource is approved for deletion by this document.

## 2. Completed runtime stages

The approved runtime teardown proceeded in reverse dependency order:

1. `frontend-delivery`;
2. Kubernetes/controller-owned external resources;
3. `rag-runtime`;
4. `eks-runtime`;
5. `stateful-dependencies`;
6. `runtime-dependencies`;
7. `network`.

The final network execution, run `29899676188`, proved the following:

- the fresh destroy plan contained only `aws_vpc.runtime`;
- the focused recovery found one non-default security group inside the exact state-owned VPC;
- the security-group dependency and VPC were removed;
- the reviewed saved destroy plan applied successfully;
- the network Terraform managed-instance count became zero.

The final runtime-dependencies execution, run `29894803446`, proved the following before its residual-check false negative:

- 20 ECR image digests were removed;
- the exact `terraformers-backend` repository was removed;
- the reviewed saved destroy plan applied successfully;
- the runtime-dependencies Terraform managed-instance count became zero.

The stateful, EKS, RAG, frontend, and Kubernetes-owner stages had already reached their approved deletion outcomes before the network closure.

## 3. False-negative workflow conclusions

Several GitHub Actions runs were marked failed after the destructive work had already completed. These failures must not be interpreted as evidence that the corresponding Terraform state or primary resource still exists.

### Frontend delivery

Run `29887177031` completed the material frontend deletion but the residual check treated an empty CloudFront list response as a failure.

### Stateful dependencies

Run `29892523925` reached state zero, then checked asynchronous RDS automated-backup, managed-Secret, or Cognito cleanup before AWS control-plane convergence. The same state and code later passed after convergence. PR #104 added bounded convergence evidence.

### Runtime dependencies

Run `29893725860` removed 15 of 16 resources but could not delete the non-empty ECR repository because a destroy-only plan did not persist the runner-only `force_delete` override. PR #105 added exact ECR image purge before the reviewed saved plan.

Run `29894803446` then removed the repository and reached state zero. Its final failure was caused by residual code that did not normalize an empty SQS response and counted a Secret scheduled for deletion as active runtime.

### Network

Run `29895677745` removed 15 of 16 network resources. A controller-created non-default security group prevented VPC deletion, while the workflow waited inside the provider delete timeout without first inventorying VPC dependencies.

PR #106 added exact state-owned VPC recovery. Run `29899676188` removed the security group and VPC and reached state zero. Its final failure was caused by an account-wide Project-tag query rather than verification of the exact deleted VPC.

These failed conclusions are preserved as incident evidence. The destructive workflows must not be rerun solely to obtain a green status.

## 4. Correct verification model

Terraform state zero is necessary but not sufficient. Runtime closure is verified using both:

- zero managed instances in all six runtime Terraform states;
- the Kubernetes owner-removal marker;
- exact-name or exact-identity AWS absence checks;
- explicit classification of Secrets pending deletion;
- exclusion of the documented bootstrap plane.

The canonical final check is `.github/workflows/aws-runtime-closure-verification.yml`. It is read-only and does not run Terraform apply/destroy, Kubernetes mutation, or service cleanup.

The workflow verifies:

- `frontend-delivery`, `rag-runtime`, `eks-runtime`, `stateful-dependencies`, `runtime-dependencies`, and `network` state counts;
- EKS, RDS, ECR, S3, SQS, AOSS, CodeBuild, Cognito, CloudFront, the exact runtime VPC name, ELBv2 resources, and project log groups;
- active runtime Secrets separately from Secrets already pending deletion;
- the Kubernetes owner-removal marker;
- that foundation was neither checked nor deleted.

A Secret pending deletion is not treated as an active service runtime. Its count remains visible in the sanitized evidence and must be reconsidered before the final zero-resource bootstrap closure.

## 5. Lessons retained for operations and interviews

The teardown exposed three design defects that are more important than the individual AWS errors.

1. A state-zero prerequisite did not prove that non-Terraform or asynchronous residuals had converged.
2. Broad account-wide name/tag scans produced false negatives after exact resources were already deleted.
3. Long provider deletion timeouts hid the first blocking VPC dependency instead of inventorying it before apply.

The corrected operating rule is:

> Resolve the exact state-owned resource, inventory external dependencies before a long delete, use bounded service-specific cleanup only where the inventory proves it is required, and verify the exact identity afterward. Do not repeat the full destructive workflow merely to change a status badge.

## 6. Remaining work

1. Merge the closure-verification source and this record after static checks.
2. Run the read-only `AWS Runtime Closure Verification` workflow once.
3. Attach its sanitized artifact result to this closure record in a documentation-only follow-up if necessary.
4. Present the remaining bootstrap/state/OIDC inventory and deletion boundary separately.
5. Require a new explicit user approval before any bootstrap, state-bucket, or OIDC mutation.

Runtime deletion is complete. Bootstrap teardown is a separate future decision, not an automatic continuation of the runtime workflow.
