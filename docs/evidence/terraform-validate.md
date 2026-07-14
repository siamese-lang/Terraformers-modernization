# Terraform Validation Evidence Template

## Scope

Terraform fmt/init/validate evidence for the public infrastructure code.

## Commands

```bash
cd infra/terraform/envs/dev
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

## Expected result

- Formatting check succeeds.
- Provider/module initialization succeeds without remote backend.
- Terraform validate succeeds.
- No secret value, tfstate, or account-specific credential is printed.

## Current state

Infrastructure code has not been imported yet. This template will be used after `infra/terraform/` is populated.
