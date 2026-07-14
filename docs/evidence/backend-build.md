# Backend Build Evidence Template

## Scope

Backend Maven and Docker build validation.

## Commands

```bash
cd backend
mvn -q test
mvn -q -DskipTests package
docker build -t terraformers-backend:local .
```

## Expected result

- Maven test succeeds.
- Maven package creates a Spring Boot jar under `backend/target/`.
- Docker image build succeeds.
- No secret value is printed in logs.

## Evidence to attach later

- GitHub Actions run link or sanitized screenshot.
- Local command output with account-specific values removed.
- Docker image build summary.

## Notes

Do not paste raw logs if they contain tokens, account ids, private endpoints, or credentials.
