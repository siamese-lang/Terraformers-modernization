# Runtime Contract Verification Evidence - 2026-07-14

## 1. Scope

This evidence records the runtime contract verification result reported from the local Git Bash environment.

This is not AWS deployment evidence. It verifies that the public deployment contract is structurally safe and renderable before real environment overlays are introduced.

The verification covers:

- Kubernetes base rendering through `kubectl kustomize`;
- public-safe manifest checks;
- exclusion of placeholder Secret resources from the public base;
- Terraform runtime contract formatting, validation, and example plan generation.

## 2. Command

Executed from the repository root:

```bash
bash scripts/checks/runtime-contract-verification.sh
```

The script performs:

```text
kubectl kustomize infra/kubernetes/base
terraform init -backend=false -input=false
terraform fmt -check
terraform validate
terraform plan -input=false -lock=false -var-file=terraform.tfvars.example
```

## 3. Observed result

The verification was reported as passing after two corrections:

1. the Kubernetes Secret example check was narrowed to actual YAML resource entries instead of comments;
2. Terraform files were formatted to satisfy `terraform fmt -check`.

Successful verification means the script completed with:

```text
[runtime-contract] verification completed
```

## 4. Meaning

This proves the public runtime contract currently satisfies the baseline checks:

```text
Kubernetes base renders ConfigMap, ServiceAccount, Deployment, and Service
Kubernetes base does not render placeholder Secret resources
Kubernetes base does not include account-specific IAM ARNs
Kubernetes base does not include 12-digit account-like identifiers
Terraform runtime contract is formatted, validates, and plans with the example tfvars
```

This supports the project boundary that public baseline manifests and Terraform examples should show deployment shape without exposing environment-specific secrets or account identifiers.

## 5. Limitations

This evidence does not prove:

- Kubernetes rollout to a real cluster;
- valid AWS IAM permissions;
- External Secrets or SecretStore integration;
- real RDS, S3, SQS, Cognito, Bedrock, or OpenSearch/AOSS connectivity;
- production adapter behavior;
- Docker image build or image runtime behavior.

Those should be validated in later stages after the backend image and environment-specific overlays are introduced.
