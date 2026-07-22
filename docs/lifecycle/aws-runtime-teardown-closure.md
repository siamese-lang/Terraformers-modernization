# AWS Runtime Teardown Closure

Status: **historical pre-state-bucket-deletion runtime closure; later project-scoped zero-resource proof complete**

Runtime closure source commit: `e2a6cb5cc2d0a6879456bbcf6159b16d45e3d582`

Read-only closure verification:

- workflow: `AWS Runtime Closure Verification`;
- run: `29904386655`;
- job: `88872221575`;
- artifact: `aws-runtime-closure-evidence`, ID `8523216242`;
- artifact digest: `sha256:6df5028ea5a5a7c6503297b193a5a29100fe3c33366689731eac38edc3111072`;
- result: `passed_with_pending_secret_deletion`.

## 1. Closure boundary

This record closes only the Terraformers runtime plane.

The following bootstrap resources are intentionally outside this closure:

- Terraform state bucket and its object versions;
- GitHub Actions OIDC provider;
- foundation, plan, apply, and final teardown identities and policies;
- GitHub repository and Environment configuration.

No bootstrap resource is approved for deletion by this document. Bootstrap inventory later passed, but deletion-command review and separate execution approval remain pending; account-wide zero-resource proof is not complete.

## 2. Verified runtime closure result

The final read-only workflow completed every step successfully. It did not run Terraform plan/apply/destroy, mutate Kubernetes, or call an AWS delete API.

All six runtime Terraform states contain zero managed instances:

| State | Managed instances |
|---|---:|
| `frontend-delivery` | 0 |
| `rag-runtime` | 0 |
| `eks-runtime` | 0 |
| `stateful-dependencies` | 0 |
| `runtime-dependencies` | 0 |
| `network` | 0 |

The Kubernetes owner-removal marker is valid: `kubernetes_owners_removed=true`.

Exact runtime residual counts:

| Resource group | Count |
|---|---:|
| EKS cluster | 0 |
| RDS instance | 0 |
| ECR repository | 0 |
| project S3 buckets | 0 |
| project SQS queues | 0 |
| active runtime Secret | 0 |
| AOSS collection | 0 |
| CodeBuild ingestion project | 0 |
| Cognito user pool | 0 |
| CloudFront distribution | 0 |
| CloudFront VPC origin | 0 |
| exact runtime VPC | 0 |
| project load balancer | 0 |
| project target group | 0 |
| project CloudWatch log group | 0 |

One Secret is still visible only with `include-planned-deletion`:

- pending runtime Secret deletion count: `1`;
- active runtime Secret count: `0`;
- classification: deletion tombstone, not active service runtime.

This tombstone can temporarily block reuse of the same Secret name. It must be checked again before a final zero-AWS-resource declaration or immediate redeployment, but it does not reopen runtime deletion.

The verification explicitly recorded:

- `foundation_checked=false`;
- `foundation_deleted=false`.

## 3. Completed runtime stages

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

The stateful, EKS, RAG, frontend, and Kubernetes-owner stages had already reached their approved deletion outcomes before network closure.

## 4. False-negative workflow conclusions

Several destructive runs were marked failed after the destructive work had completed. They are incident evidence, not proof that runtime resources remain.

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

The read-only run `29904386655` replaced those broad residual assumptions with exact checks and passed. Destructive workflows must not be rerun solely to obtain green historical status.

## 5. Correct verification model

Terraform state zero is necessary but not sufficient. Runtime closure requires all of the following:

- zero managed instances in all six runtime Terraform states;
- a valid Kubernetes owner-removal marker;
- exact-name or exact-identity AWS absence checks;
- explicit classification of Secrets pending deletion;
- exclusion of the documented bootstrap plane.

The canonical final check is `.github/workflows/aws-runtime-closure-verification.yml`. It is read-only and produced only sanitized counts.

## 6. Lessons retained for operations and interviews

The teardown exposed three process defects that are more important than the individual AWS errors.

1. A state-zero prerequisite did not prove that non-Terraform or asynchronous residuals had converged.
2. Broad account-wide name/tag scans produced false negatives after exact resources were already deleted.
3. Long provider deletion timeouts hid the first blocking VPC dependency instead of inventorying it before apply.

The corrected operating rule is:

> Resolve the exact state-owned resource, inventory external dependencies before a long delete, use bounded service-specific cleanup only where the inventory proves it is required, and verify the exact identity afterward. Do not repeat the full destructive workflow merely to change a status badge.

## 7. Subsequent lifecycle result

Bootstrap and remaining live-smoke resources were later deleted. Project-scoped zero-AWS-resource proof completed on 2026-07-22. Run `29904386655` remains the pre-state-bucket-deletion proof that all six runtime states had zero managed instances; remote state history was then intentionally removed with the state bucket. See [final proof](aws-final-zero-resource-proof.md).
