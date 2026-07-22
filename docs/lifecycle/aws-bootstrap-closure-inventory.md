# AWS Bootstrap Closure Inventory

This is the bounded, read-only prerequisite for reviewing bootstrap deletion commands after the user selected `DELETE_BOOTSTRAP_FOR_ZERO_RESOURCE_PROOF`. It is not a deletion procedure and does not grant execution approval.

## Execution environment

Run this script only in **AWS CloudShell** or an independent administrator Linux shell with Bash, AWS CLI, and `jq`. It is not intended for Windows Git Bash. The caller must be an identity outside `terraformers-live-terraform-plan`, `terraformers-live-terraform-apply`, and `terraformers-live-teardown`.

## Required inputs and command

Use the existing GitHub Environment/workflow value for `STATE_PREFIX` (`AWS_TERRAFORM_STATE_PREFIX`); do not create or guess a new prefix. The documented defaults are account `024863981627`, region `ap-northeast-2`, and bucket `terraformers-modernization-024863981627-apne2-state`.

```bash
export EXPECTED_ACCOUNT_ID=024863981627
export AWS_REGION=ap-northeast-2
export STATE_BUCKET=terraformers-modernization-024863981627-apne2-state
export STATE_PREFIX='<the existing AWS_TERRAFORM_STATE_PREFIX value>'
bash scripts/teardown/inventory_bootstrap_closure.sh
```

The only generated files are local CloudShell results:

```text
artifacts/bootstrap-closure-inventory/bootstrap-closure-inventory.json
artifacts/bootstrap-closure-inventory/execution-summary.txt
```

Do not commit these generated results. They contain sanitized counts, booleans, and exact resource identities only.

## What it checks

The inventory confirms the caller account and independent identity; counts managed instances in all six runtime states; reads the bootstrap state for managed/data counts and managed addresses; and counts versions, delete markers, current objects, multipart uploads, and lock versions in the exact state bucket. It also inventories the three exact Terraformers roles and `terraformers-` customer-managed policies without recording policy documents.

It reads the exact GitHub OIDC provider, identifies every trusting role by inspecting each role's assume-role policy in memory, and blocks review readiness if a non-Terraformers role trusts it. Finally, it classifies the exact runtime Secret as active, pending deletion, or absent using `--include-planned-deletion`.

## Interpreting the contract

`inventory_contract=ready_for_deletion_command_review` means only that the read-only preconditions are present: runtime states are zero, bootstrap state and bucket are readable/present, OIDC ownership is Terraformers-only, the caller is independent, and all inventory API calls succeeded. It is **not** authorization to run a delete command.

The other values are `blocked_by_runtime_state`, `blocked_by_oidc_shared_ownership`, and `blocked_by_inventory_error`. Resolve or explicitly review the reported bounded condition before preparing commands.

## Recorded read-only result

The inventory has now passed. The caller was `arn:aws:iam::024863981627:user/admin-user` and `independent_identity_confirmed=true`. All six runtime state counts were 0. Bootstrap measured 16 managed resources and 9 data sources with no expected-address difference. The state bucket was versioned and contained 231 object versions, 159 delete markers, 8 current objects, 0 multipart uploads, and 318 lock-object versions. The OIDC provider was present with Terraformers-only trust, the three required Terraformers roles were present, active runtime Secret count was 0, and pending runtime Secret deletion count was 1.

`inventory_api_error_labels=[]` and `inventory_contract=ready_for_deletion_command_review`. This does not classify the separately discovered live-smoke IRSA role/policy or possible EKS OIDC-provider residue, and it does not approve a mutation.

## Approval boundary

No AWS mutation is implemented by this inventory. After a passing result, review the exact deletion commands once, then obtain separate explicit execution approval. IAM, OIDC, state-bucket, object-version, Terraform, and Secret mutations remain outside this scope.
