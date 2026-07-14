# Infrastructure

This directory is reserved for Terraform and Kubernetes infrastructure code that will be imported after backend baseline verification.

Planned structure:

```text
infra/
  terraform/
    envs/dev/
    modules/
  kubernetes/
    backend/
    bedrock/
    secrets/
    argocd/
```

Import rules:

- Do not commit `terraform.tfstate`, real `terraform.tfvars`, kubeconfig, or account-specific secrets.
- Provide `*.tfvars.example` only.
- Keep Terraform validation runnable with `terraform init -backend=false` before enabling remote state.
- Keep AWS deployment workflows dependent on repository `secrets.*` and `vars.*`, not hardcoded values.
