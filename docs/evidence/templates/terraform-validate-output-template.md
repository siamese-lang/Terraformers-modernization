# Terraform Validate Output Template

```text
$ terraform fmt -check -recursive
<no output or formatted file list>

$ terraform init -backend=false
<redacted output>

$ terraform validate
Success! The configuration is valid.
```

Redaction checklist:

- Remove account ids.
- Remove private ARNs.
- Remove backend bucket names if account-specific.
- Do not include tfstate or tfvars contents.
