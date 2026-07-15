# Terraform Backend Stateful Dependencies

## 1. Purpose

This document describes the Terraform scaffold for backend stateful dependencies that are required before the backend can run with the `prod` Spring profile.

The previous backend runtime dependency scaffold creates ECR, S3, SQS, and a Secrets Manager secret container. This scaffold adds the stateful application dependencies that fill the remaining required runtime values:

```text
RDS MariaDB
Cognito user pool
Cognito app client
```

This is still not a full EKS deployment.

## 2. Terraform path

```text
infra/terraform/envs/backend-stateful-dependencies
```

## 3. What this creates

```text
aws_security_group.backend_database
aws_db_subnet_group.backend
aws_db_instance.backend
aws_cognito_user_pool.backend
aws_cognito_user_pool_client.backend
```

## 4. Required existing inputs

This scaffold intentionally does not create a VPC or EKS cluster. It expects an existing network boundary:

```text
vpc_id
private_subnet_ids
allowed_app_security_group_ids
```

For an EKS environment, `allowed_app_security_group_ids` should represent the backend runtime boundary that is allowed to connect to MariaDB on port 3306. In a later production-grade EKS PR, this can be tied to the cluster/node/pod security group model.

## 5. Outputs used by backend runtime Secret

After apply, these outputs map to backend runtime environment variables:

```text
spring_datasource_url       -> SPRING_DATASOURCE_URL
database_username           -> SPRING_DATASOURCE_USERNAME
database_password input     -> SPRING_DATASOURCE_PASSWORD
cognito_region              -> COGNITO_REGION
cognito_user_pool_id        -> COGNITO_USER_POOL_ID
cognito_user_pool_client_id -> COGNITO_USER_POOL_CLIENT_ID
cognito_jwks_url            -> COGNITO_JWKS_URL
```

The database password is intentionally not output. Supply it from a secure source and write it into the runtime Secret workflow separately.

## 6. Validation

Static validation:

```bash
bash scripts/checks/terraform-static-verification.sh
```

Or through GitHub Actions:

```text
Terraform Static Verification
```

## 7. Apply sequence

Recommended sequence for a real AWS validation environment:

```text
1. Confirm VPC and private subnet IDs.
2. Confirm backend/EKS runtime security group ID that should reach RDS.
3. Copy terraform.tfvars.example to an untracked tfvars file.
4. Replace placeholder VPC/subnet/security group values.
5. Supply database_password from a secure source.
6. terraform init
7. terraform plan -var-file=<untracked-runtime.tfvars>
8. terraform apply -var-file=<untracked-runtime.tfvars>
9. Copy outputs into backend runtime Secret wiring.
```

Do not commit real tfvars containing account, network, or password values.

## 8. Current exclusions

This scaffold does not create:

```text
VPC
EKS cluster
EKS node groups
IRSA role or policy binding
Secrets Manager secret version
Kubernetes Secret or ExternalSecret
OpenSearch/AOSS
Bedrock model access
production rollout workflow
```

Those remain separate PRs because they introduce different operational risks and validation gates.

## 9. Portfolio explanation

```text
Terraformers modernization separates backend production runtime dependencies into bounded Terraform layers. ECR/S3/SQS/Secrets Manager are handled as runtime integration resources, while RDS MariaDB and Cognito are handled as stateful application dependencies. The database and identity layer is defined with private networking assumptions and public-safe examples, so the project can explain how the backend would move from local/kind validation toward an AWS runtime without committing account-specific or secret values.
```
