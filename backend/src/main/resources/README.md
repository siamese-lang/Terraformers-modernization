# Backend Resources

## Configuration files

- `application.yml`: local/default profile. It disables datasource/JPA/Flyway auto-configuration so the public baseline can start without real cloud credentials.
- `application-prod.yml`: production runtime contract. It expects datasource, Cognito, S3, and SQS values to be injected at runtime.
- `application-prod.example.yml`: placeholder-only example for required runtime values. Do not put real credentials here.

## Migration files

- `db/migration/V20260714_001__baseline_backend_schema.sql`: baseline RDB schema for the public backend modernization track.

## Secret handling rule

Do not commit real values for database password, AWS account id, access token, Cognito secret, SQS URL, or bucket names that reveal a private environment. Use examples, placeholders, repository variables, GitHub secrets, Kubernetes Secrets, or External Secrets instead.
