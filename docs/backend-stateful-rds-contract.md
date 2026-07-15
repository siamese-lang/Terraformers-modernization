# Backend Stateful RDS Contract

This document records the source-reuse-first alignment for `infra/terraform/envs/backend-stateful-dependencies`.

## Source review

```text
AWS-Terraformers/Terraformers:
- Original backend stored project, file, and Terraform-code metadata through DynamoDB/S3 service logic.
- The modernization target should preserve the product flow, not restore DynamoDB-era persistence as the primary stateful path.

AWS-Terraformers/Infra-code:
- Original infrastructure separated network, EKS, backend-app, IAM, Secrets Manager, and application runtime resources.
- The original RDS path was not the canonical product path, but the network/EKS composition still supplies the target VPC/private-subnet/security-group boundaries.

siamese-lang/rdb-refactor:
- `modules/rds-mariadb` defines the RDS MariaDB contract with a DB subnet group, security-group-based ingress rules, RDS-managed master password, and JDBC URL output.
- `application-prod.properties` expects `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, and `SPRING_DATASOURCE_PASSWORD`, with Hibernate `ddl-auto=validate` and Flyway enabled.
- `docs/operations/schema/README.md` identifies Flyway migrations as the canonical schema source and manual SQL only as an emergency fallback.
```

## Reuse / modify / add / exclude

```text
Reuse:
- rdb-refactor RDS MariaDB module contract
- RDS-managed master password secret ARN output pattern
- JDBC URL output with explicit SSL params
- security-group-based MariaDB ingress rule pattern
- production datasource contract from application-prod.properties

Modify:
- Keep the existing modernization `backend-stateful-dependencies` env rather than copying the whole rdb-refactor module tree.
- Replace inline dynamic SG ingress blocks with explicit `aws_vpc_security_group_ingress_rule` resources.
- Default to `manage_master_user_password=true` so Terraform does not require committing or passing a DB password by default.
- Add RDS lifecycle and sizing knobs already present in the rdb-refactor module.

Add:
- `database_master_user_secret_arn` output for operator/runtime secret wiring.
- `database_jdbc_ssl_params` variable and SSL-param JDBC output.
- RDS instance/subnet-group identity outputs for evidence and downstream runtime packaging.

Exclude:
- No Terraform apply automation.
- No kubectl apply automation.
- No External Secrets installation.
- No generated Kubernetes Secret value from the RDS password.
- No public DB exposure.
- No DynamoDB-era application state restoration.
- No Terraform execution UI/API.
```

## Runtime secret boundary

The backend runtime still needs:

```text
SPRING_DATASOURCE_URL
SPRING_DATASOURCE_USERNAME
SPRING_DATASOURCE_PASSWORD
```

This Terraform env can now output:

```text
spring_datasource_url

database_username

database_master_user_secret_arn
```

The actual password value should be resolved by an operator-approved path before rendering the runtime Secret. For the first private live smoke, that can be a manual retrieval step from the RDS-managed secret. A later External Secrets PR can replace that manual step, but this PR intentionally does not install or enable External Secrets.

## Flyway and schema validation boundary

The RDS contract is only the infrastructure boundary. Backend startup still depends on the application schema contract:

```text
spring.flyway.enabled=true
spring.jpa.hibernate.ddl-auto=validate
```

Therefore, live validation should treat backend startup failure from missing tables or mismatched columns as a schema/migration issue, not as a network or RDS provisioning issue.

## Verification boundary

`Terraform Static Verification` must run on this PR before merge. The workflow PR trigger is enabled separately on `main`; this document update exists to create a new PR synchronize event after that trigger is available.

## Stop condition

This alignment is complete when:

```text
- Terraform Static Verification passes.
- backend-stateful-dependencies validates with RDS-managed password enabled by default.
- downstream output names still support the AWS runtime input bundle path.
- database_master_user_secret_arn is available for controlled secret wiring.
- no apply automation, public exposure, External Secrets installation, or adapter enablement is introduced.
```
