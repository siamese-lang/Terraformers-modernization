# Pre-merge Live Deployment Plan Dispatch

## Why the standalone workflow returns 404

GitHub registers a manually dispatched workflow only when that workflow file exists on the repository default branch.

During Draft PR #32, `.github/workflows/aws-live-terraform-plan.yml` exists only on `agent/rdb-domain-realignment`. Therefore this command is intentionally unavailable before merge:

```powershell
gh workflow run aws-live-terraform-plan.yml --ref agent/rdb-domain-realignment
```

The `--ref` option selects which branch version to run; it does not register a workflow file that is absent from the default branch.

## Registered pre-merge entry

Use the workflow that already exists on `main`:

```text
.github/workflows/runtime-contract-verification.yml
```

The branch version adds a third job:

```text
Generate live deployment execution plan
```

That job:

- reads `config/live-deployment-stages.json`
- generates the canonical 12-stage execution plan
- uploads `live-deployment-execution-plan-evidence`
- performs no AWS authentication
- performs no Terraform plan/apply/destroy
- performs no Kubernetes or Helm mutation

## Pre-merge command

```powershell
$Repo = "siamese-lang/Terraformers-modernization"
$Branch = "agent/rdb-domain-realignment"

gh workflow run runtime-contract-verification.yml `
  --repo $Repo `
  --ref $Branch
```

Expected jobs:

```text
Runtime contract baseline
Build images and dry-run deployment packages
Generate live deployment execution plan
```

## After merge

Once `.github/workflows/aws-live-terraform-plan.yml` exists on `main`, it becomes a registered manual workflow. Only then may it be dispatched directly with `execute_live_plan=false` or, after AWS prerequisites are reviewed, `execute_live_plan=true`.

Direct workflow registration does not approve AWS mutation. The standalone workflow remains plan-only and contains no Terraform apply/destroy, image push, Kubernetes apply, Helm installation, S3 sync, or CloudFront invalidation.
