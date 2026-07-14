# Runtime Contract Verification

## 1. Purpose

This document explains the static verification step for the public-safe runtime contract.

The goal is to catch deployment-contract mistakes before real AWS deployment, especially:

- placeholder Secret resources accidentally rendered by the public Kubernetes base;
- account-specific IAM ARNs or 12-digit account-like identifiers committed to public manifests;
- missing backend adapter switches in the ConfigMap;
- Terraform runtime contract shape drift;
- example values that look like real deployment values.

## 2. Verification script

Run from the repository root:

```bash
bash scripts/checks/runtime-contract-verification.sh
```

The script performs three groups of checks.

### 2.1 Kubernetes base rendering

It renders the public base:

```bash
kubectl kustomize infra/kubernetes/base
```

Expected resources:

- ConfigMap;
- ServiceAccount;
- Deployment;
- Service.

The rendered base must not contain:

- a Secret resource;
- account-specific IAM role ARNs;
- 12-digit account-like identifiers;
- `replace-me` placeholder values.

`backend-secret.example.yaml` is intentionally excluded from the `resources` list in `kustomization.yaml`. The file may be mentioned in comments for documentation, but it must not be rendered as a base Secret resource.

### 2.2 Public-safe example checks

The script checks committed example files for values that should not appear in a public baseline:

- `infra/kubernetes/base/backend-secret.example.yaml`;
- `infra/kubernetes/base/backend-serviceaccount.yaml`;
- `infra/terraform/runtime-contract/terraform.tfvars.example`.

These files may contain placeholder tokens such as `<upload-bucket-name>`, but they must not contain real account IDs, real IAM role ARNs, or deployment-specific queue URLs.

### 2.3 Terraform runtime contract validation

The script validates the Terraform runtime contract shape:

```bash
cd infra/terraform/runtime-contract
terraform init -backend=false -input=false
terraform fmt -check
terraform validate
terraform plan -input=false -lock=false -var-file=terraform.tfvars.example
```

The example file is for contract validation only. It must not be applied to a real AWS account as-is.

## 3. GitHub Actions workflow status

The matching workflow is:

```text
.github/workflows/runtime-contract-verification.yml
```

During the public baseline construction phase, this workflow is intentionally **manual-only**.

```text
on: workflow_dispatch
```

It should be run manually when the Kubernetes base, Terraform runtime contract, or verification script changes. Automatic push/PR execution should be re-enabled only after the backend baseline and runtime contract are stable enough that repeated public red checks no longer obscure meaningful progress.

## 4. Failure interpretation

| Failure | Likely issue | Fix |
| --- | --- | --- |
| `Base kustomization must not render placeholder Secret resources` | `backend-secret.example.yaml` was rendered as a Secret resource | Remove it from `kustomization.yaml`; create real Secret through overlay or External Secrets |
| `backend-secret.example.yaml must not be included in base kustomization resources` | `backend-secret.example.yaml` was added as a YAML list item under resources | Remove the resource entry; comments mentioning the example file are allowed |
| `Base manifest must not contain account-specific IAM ARNs` | IRSA role ARN was committed to base | Move annotation to environment-specific overlay |
| `Base manifest must not contain 12-digit account-like identifiers` | Account ID or account-looking placeholder was committed | Replace with `<account-id>` style placeholder or remove from base |
| `Terraform variable contract validates` fails | Runtime contract object shape drifted | Align `variables.tf`, `locals.tf`, and `terraform.tfvars.example` |
| `terraform fmt -check` fails | Terraform formatting drift | Run `terraform fmt` in `infra/terraform/runtime-contract` |

## 5. Portfolio explanation

```text
배포 manifest와 runtime 변수도 포트폴리오 품질에 포함된다고 보고, public base에 Secret이나 계정별 IAM ARN이 들어가지 않도록 정적 검증을 추가했습니다. 다만 아직 baseline 구축 중이므로 자동 CI가 계속 실패 표시를 만들지 않게 수동 실행으로 두고, backend와 runtime contract가 안정화된 뒤 push/PR 자동 검증을 다시 켤 계획입니다.
```
