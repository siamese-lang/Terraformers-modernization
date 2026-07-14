# Security and Secret Handling

## Secret handling policy

Do not commit:

- AWS access keys or session tokens
- GitHub tokens
- DB passwords
- Cognito secrets
- kubeconfig files
- Terraform state files
- real `terraform.tfvars`
- private account-specific values unless explicitly redacted

## Runtime configuration

Use placeholders, environment variables, repository secrets, repository variables, Kubernetes Secrets, External Secrets, or Secrets Manager references.

## Evidence handling

Evidence must be sanitized before commit. Remove tokens, account ids, passwords, private ARNs, internal endpoint values, and raw logs that reveal sensitive data.

## Reporting accidental exposure

If a secret is accidentally committed, rotate the secret immediately and remove it from the repository history if needed. Do not rely only on deleting the latest file content.
