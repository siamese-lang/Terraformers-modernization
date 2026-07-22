# AWS Bootstrap Closure Decision

Status: **decision pending; no bootstrap mutation approved**

This document defines the remaining AWS boundary after verified runtime closure. It is a decision record, not authorization to delete resources.

## 1. Evidence basis

Runtime closure was verified by read-only run `29904386655` against integration commit `e2a6cb5cc2d0a6879456bbcf6159b16d45e3d582`.

The closure artifact proved:

- all six runtime Terraform states contain zero managed instances;
- all exact active runtime AWS resource counts are zero;
- the Kubernetes owner-removal marker is valid;
- active runtime Secret count is zero;
- one runtime Secret remains only as a pending-deletion tombstone;
- foundation was not checked or deleted.

The completed Terraform state inventory proved that the `bootstrap` state contains 16 managed resources and 9 data sources. Runtime teardown did not include or update this state.

## 2. Terraform-managed bootstrap resources

The 16 managed addresses are:

```text
aws_iam_policy.terraform_apply_operations_visibility_create
aws_iam_role.terraform_apply
aws_iam_role.terraform_plan
aws_iam_role_policy.terraform_apply_iam_mutation
aws_iam_role_policy.terraform_apply_rag_runtime_create
aws_iam_role_policy.terraform_apply_state_access
aws_iam_role_policy.terraform_state_access
aws_iam_role_policy_attachment.terraform_apply_operations_visibility_create
aws_iam_role_policy_attachment.terraform_apply_read_only
aws_iam_role_policy_attachment.terraform_plan_read_only
aws_s3_bucket.terraform_state
aws_s3_bucket_ownership_controls.terraform_state
aws_s3_bucket_policy.terraform_state
aws_s3_bucket_public_access_block.terraform_state
aws_s3_bucket_server_side_encryption_configuration.terraform_state
aws_s3_bucket_versioning.terraform_state
```

Primary live identities represented by this state:

- `terraformers-live-terraform-plan`;
- `terraformers-live-terraform-apply`.

The state bucket is:

```text
terraformers-modernization-024863981627-apne2-state
```

It is versioned, encrypted, private, and still required to read the bootstrap and completed runtime state histories.

The earlier inventory counted 175 object versions and 126 delete markers. Teardown runs have created additional state versions since that snapshot. A deletion procedure must therefore enumerate and purge all current versions and markers rather than depend on the historical count.

## 3. External bootstrap resources

### GitHub OIDC provider

The account inventory identified one GitHub Actions OIDC provider for `token.actions.githubusercontent.com`.

It is outside Terraform state. At inventory time every role trusting it was Terraformers-specific, so it is classified as a project-dedicated external bootstrap resource rather than shared account infrastructure.

Three former trusting roles belonged to runtime delivery states and were removed when those states reached zero:

- Backend image publisher;
- frontend delivery;
- RAG corpus ingestion dispatcher.

Known remaining OIDC identities are:

- Terraform live-plan role;
- Terraform live-apply role;
- final runtime-teardown role used by the successful closure workflow.

The final teardown role is not represented by the 16 bootstrap state addresses. Its exact role and policy attachments must be included in the final IAM removal pass.

Immediately before deletion, list the provider's current trusting roles once and reject the deletion if any non-Terraformers role is present. This is a bounded ownership check, not a new discovery phase.

### GitHub configuration

GitHub Environments, approval rules, variables, and encrypted values are external configuration, not AWS resources.

Decision already recorded:

- retain them for possible redeployment;
- do not copy encrypted values into documentation;
- update resource identifiers only during a future redeployment.

## 4. Remaining pending-deletion Secret

The runtime closure artifact reported:

```text
active_runtime_secret_count=0
pending_runtime_secret_deletion_count=1
```

This is not active runtime. It is still relevant to:

- immediate reuse of the same Secret name;
- a strict final claim that the AWS account contains zero Terraformers-attributable resources.

Before final bootstrap deletion, check the exact Secret name once. If the tombstone is still present, either wait for AWS deletion convergence or explicitly exclude the pending tombstone from the zero-resource claim until it disappears. Do not recreate or repeatedly delete it.

## 5. Decision A - Retain bootstrap

Retain:

- state bucket and its version history;
- Terraform live-plan and live-apply roles/policies;
- final teardown role;
- project GitHub OIDC provider;
- GitHub Environments and variables.

### Consequences

Advantages:

- fastest future redeployment path;
- existing remote-state and OIDC foundation remains available;
- no independent CloudShell/admin closure operation is required.

Limitations:

- the AWS account is not at zero Terraformers resources;
- stale IAM permissions remain and must be maintained;
- versioned state objects continue to occupy S3 storage;
- the portfolio must say runtime resources were removed while bootstrap was intentionally retained.

This is a valid lifecycle choice when near-term redeployment is likely.

## 6. Decision B - Delete bootstrap for zero-resource proof

Delete all remaining Terraformers AWS bootstrap resources and retain only GitHub configuration and repository evidence.

### Consequences

Advantages:

- strongest zero-AWS-resource closure;
- no stale project IAM/OIDC boundary remains;
- no ongoing state-bucket storage.

Limitations:

- remote Terraform state history is permanently removed;
- future deployment must recreate the state bucket, GitHub OIDC provider, and foundation roles from the bootstrap runbook;
- the final operation cannot depend exclusively on the GitHub OIDC roles being deleted;
- an independent administrator or AWS CloudShell identity is required.

### Bounded deletion order

The final operation must use an independent administrator/CloudShell identity and follow this order:

1. confirm all six runtime states remain at zero and no runtime workflow is running;
2. check the exact pending runtime Secret tombstone once;
3. record only sanitized bootstrap state addresses and counts; do not export raw state to Git;
4. list current roles trusting the project GitHub OIDC provider and require that every role is Terraformers-specific;
5. detach managed policies and remove inline policies from Terraform plan/apply and final teardown roles;
6. delete the Terraform plan/apply roles and final teardown role;
7. delete Terraformers customer-managed IAM policies after all attachments are gone;
8. delete the project-dedicated GitHub OIDC provider after no role trusts it;
9. abort incomplete multipart uploads in the state bucket;
10. delete every state object version, delete marker, and Terraform lock object version;
11. delete the bucket policy and then the empty state bucket;
12. run one final read-only residual check for the exact bucket, OIDC provider, IAM names, and pending Secret.

Do not run a broad `terraform destroy` that attempts to remove its own remote backend bucket. The state bucket and final identity require the independent final procedure above.

## 7. Approval boundary

Runtime teardown approval does not authorize either decision.

The user must explicitly choose one of the following:

```text
RETAIN_BOOTSTRAP_FOR_REDEPLOYMENT
```

or

```text
DELETE_BOOTSTRAP_FOR_ZERO_RESOURCE_PROOF
```

Choosing deletion authorizes planning and review of the final bounded CloudShell/admin procedure, not immediate deletion. The exact current IAM/OIDC/state-bucket inventory and deletion commands must be reviewed once before execution.
