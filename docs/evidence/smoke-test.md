# Smoke Test Evidence Template

## Scope

Post-deploy backend/API smoke validation.

## Minimum checks

```bash
curl -i <backend-base-url>/actuator/health
curl -i <backend-base-url>/internal/runtime/required-config
```

Future checks after actual API import:

```bash
curl -i <backend-base-url>/api/public-projects
curl -i <backend-base-url>/api/project-tree/<project-id>
curl -i <backend-base-url>/api/terraform/logs?projectId=<project-id>
```

## Expected result

- Health endpoint returns success.
- Required config endpoint shows key presence only.
- Protected APIs return correct 401/200 boundaries.
- S3/SQS/RDS errors are identifiable from backend logs.

## Notes

Actual API smoke scripts will be added after safe backend API import.
