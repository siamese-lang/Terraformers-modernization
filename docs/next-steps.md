# Next Steps

## 1. Immediate validation

1. Check GitHub Actions results for:
   - Backend Maven Verification
   - Backend Image Build Verification
2. If either workflow fails, fix the public backend baseline before importing more code.
3. Run local verification if needed:

```bash
bash scripts/checks/backend-local-verification.sh
```

## 2. Next backend import

Import only public-safe backend code that supports the backend/cloud infrastructure story:

- RDB domain entities and repositories
- service logic for projects/files/comments
- S3 object storage adapter
- SQS log polling adapter
- Cognito user mapping
- API smoke scripts

Do not import the full private repository history.

## 3. Infrastructure import

After backend baseline verification, import Terraform in this order:

1. `infra/terraform/envs/dev`
2. network/security group modules
3. ECR/RDS/S3/SQS/Secrets Manager/Cognito modules
4. Kubernetes backend/bedrock manifests
5. image publish workflows
6. Terraform plan/apply workflows

## 4. Documentation updates

After each code import, update:

- `docs/validation.md`
- `docs/runbook.md`
- `docs/evidence/*`
- `README.md`
