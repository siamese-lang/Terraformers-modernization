# Managed Secret Delivery

## Decision

The selected production contract is:

```text
Terraform outputs
  -> backend runtime configuration payload
  -> AWS Secrets Manager backend runtime secret

RDS manage_master_user_password
  -> RDS-managed Secrets Manager secret

AWS Secrets Manager
  -> External Secrets Operator
  -> terraformers-backend-runtime-secrets
  -> Spring Boot envFrom
```

External Secrets Operator is selected because the original Terraformers infrastructure and `rdb-refactor` already established this operating model. The synchronization concept and RDS `password` property mapping are reused. The legacy manifests are not copied unchanged.

## Reuse and correction

Reused:

- AWS Secrets Manager as the runtime source of truth
- ExternalSecret synchronization into a Kubernetes Secret
- RDS-managed credential lookup through the `password` property
- IRSA-based short-lived AWS authentication

Corrected for the modernized runtime:

- namespace: `terraformers-runtime`, not `default`
- target Secret: `terraformers-backend-runtime-secrets`
- API: `external-secrets.io/v1`, not the prior `v1beta1` manifest
- canonical Spring/Cognito/S3 keys only
- no `FRONTEND_URL`, `DOMAIN`, `AWS_S3_BUCKET_NAME`, static AWS credentials, or disabled adapter placeholders
- dedicated `terraformers-external-secrets` ServiceAccount and IRSA role instead of sharing the backend workload identity

## Source mapping

The backend runtime Secrets Manager container holds eight non-password values:

- `SPRING_DATASOURCE_URL`
- `SPRING_DATASOURCE_USERNAME`
- `COGNITO_REGION`
- `COGNITO_USER_POOL_ID`
- `COGNITO_USER_POOL_CLIENT_ID`
- `COGNITO_JWKS_URL`
- `S3_BUCKET_NAME`
- `ANALYSIS_RESULT_BUCKET_NAME`

The database password is not copied into that payload. ExternalSecret reads:

```text
RDS-managed secret ARN
  property: password
  -> SPRING_DATASOURCE_PASSWORD
```

The resulting Kubernetes Secret has nine keys: the eight runtime configuration values plus `SPRING_DATASOURCE_PASSWORD`.

## Identity and permission boundary

`infra/terraform/envs/eks-runtime/secret_delivery.tf` defines a dedicated IRSA trust subject:

```text
system:serviceaccount:terraformers-runtime:terraformers-external-secrets
```

Its policy is read-only and limited to:

- `backend_runtime_secret_arn`
- `database_master_user_secret_arn`

Allowed actions:

- `secretsmanager:DescribeSecret`
- `secretsmanager:GetSecretValue`

The application ServiceAccount remains `terraformers-backend`. Secret synchronization and application AWS access are separate responsibilities.

## Static package

Generate the private package from existing Terraform output JSON:

```bash
python3 scripts/deploy/build-external-secrets-runtime-package.py \
  --runtime-outputs-json artifacts/terraform/backend-runtime.json \
  --stateful-outputs-json artifacts/terraform/backend-stateful.json \
  --eks-outputs-json artifacts/terraform/eks-runtime.json \
  --output-dir artifacts/external-secrets-runtime-package
```

Generated files:

```text
backend-runtime-secret-payload.json
external-secrets-runtime.yaml
managed-secret-source-map.json
package-summary.txt
apply-order.txt
```

These files are private deployment artifacts and must not be committed or uploaded as public CI artifacts when they contain real output values.

## Current status

Implemented and statically verifiable:

- Terraform IRSA source contract
- runtime payload field mapping
- RDS-managed password property mapping
- ServiceAccount, SecretStore, and ExternalSecret rendering
- canonical nine-key target Secret contract
- rejection of legacy keys, static AWS credentials, and disabled adapter settings

Not performed:

- External Secrets Operator installation
- backend runtime Secrets Manager value mutation
- Kubernetes apply
- live SecretStore or ExternalSecret synchronization
- pod rollout

Those mutations remain behind explicit approval. The static package intentionally reports:

```text
provider_installation=required-not-performed
cluster_contact=none
```
