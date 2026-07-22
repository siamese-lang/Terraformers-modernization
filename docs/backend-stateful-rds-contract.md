# Backend Stateful RDS Contract

This document records the source-reuse-first alignment for `infra/terraform/envs/backend-stateful-dependencies`.

## Source review

```text
AWS-Terraformers/Terraformers:
- Original backend stored project, file, and Terraform-code metadata through DynamoDB/S3 service logic.
- The modernization target should preserve the product flow, not restore DynamoDB-era persistence as the primary stateful path.

AWS-Terraformers/Infra-code:
- Original infrastructure separated network, EKS, backend-app, IAM, Secrets Manager, and application runtime resources.
- The original network/EKS composition supplies the target VPC/private-subnet/security-group boundaries.

siamese-lang/rdb-refactor:
- `modules/rds-mariadb` defines the RDS MariaDB contract with a DB subnet group, security-group-based ingress, RDS-managed master password, and JDBC URL output.
- `application-prod.properties` expects `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, and `SPRING_DATASOURCE_PASSWORD`, with Hibernate `ddl-auto=validate` and Flyway enabled.
- `docs/operations/schema/README.md` identifies Flyway migrations as the canonical schema source and manual SQL only as an emergency fallback.
```

## Reuse / modify / add / exclude

```text
Reuse:
- existing modernization `backend-stateful-dependencies` env
- existing security-group-based MariaDB ingress boundary
- rdb-refactor RDS-managed password secret ARN pattern
- rdb-refactor JDBC URL output pattern
- production datasource contract from application-prod.properties

Modify:
- Keep the current modernization env instead of copying the whole rdb-refactor module tree.
- Preserve the existing SG ingress style while parameterizing the database port.
- Default the RDS instance to `manage_master_user_password=true` so Terraform does not require a committed database password.
- Add RDS lifecycle, storage, port, and JDBC SSL parameters already present in the rdb-refactor contract.

Add:
- `database_master_user_secret_arn` output for operator/runtime secret wiring.
- `database_jdbc_ssl_params` variable and SSL-param JDBC output.
- RDS instance/subnet-group identity outputs for evidence and downstream runtime packaging.
- Preserve `database_instance_id` as the provider-computed immutable `DbiResourceId` contract.
- Use `database_instance_identifier` for the user-supplied `DBInstanceIdentifier` accepted by RDS API and CLI identifier parameters.

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

`Terraform Static Verification` must pass on this PR before merge.

### Output state synchronization boundary

The existing remote state predates `database_instance_identifier`. Strict applied-state verification therefore requires a separately reviewed output-state synchronization first. That operation must remain outside the verifier and must not use the recovery apply path.

The approved operational sequence is:

1. Create a saved refresh-only plan in a private work directory below `%LOCALAPPDATA%\Terraformers\live-foundation`.
2. Store the binary plan, raw plan log, and `terraform show -json` result only in that private directory.
3. Require zero non-no-op managed resource changes, including zero add, change, delete, and replacement actions.
4. Require the only non-no-op root output change to be `database_instance_identifier` with a create/add action.
5. Stop for separate user approval before applying the saved refresh-only plan. Do not generate or apply that plan from the verifier.

After the output contract has been synchronized to remote state through a separately reviewed workflow, verify the already-applied stage with:

```bash
bash scripts/deploy/verify-applied-stateful-dependencies.sh \
  --expected-head "$(git rev-parse HEAD)"
```

The verifier performs only describe/head reads, Terraform state/output reads, and a normally locked no-change plan with a five-minute lock timeout. It records lock-object presence before the plan without assuming that an active lock is stale, reports lock acquisition failure separately, and requires the lock object to be absent after any plan that acquired it. Raw output is retained only below `%LOCALAPPDATA%\Terraformers\live-foundation`; standard output contains sanitized status fields. A detailed plan exit code other than `0` fails verification without printing the raw plan.

## Stop condition

This alignment is complete when:

```text
- Terraform Static Verification passes.
- backend-stateful-dependencies validates with RDS-managed password enabled by default.
- downstream output names still support the AWS runtime input bundle path.
- database_master_user_secret_arn is available for controlled secret wiring.
- no apply automation, public exposure, External Secrets installation, or adapter enablement is introduced.
```
