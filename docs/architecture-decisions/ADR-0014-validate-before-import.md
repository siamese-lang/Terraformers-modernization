# ADR-0014: Validate Before Importing More Code

## Status

Accepted

## Context

The repository now has a backend baseline. Importing more code before validating the baseline could make debugging harder.

## Decision

Validate the current backend baseline before importing additional private backend or infrastructure code.

Required checks:

```bash
cd backend
mvn -q test
mvn -q -DskipTests package
docker build -t terraformers-backend:local .
```

## Consequences

- Failures are easier to isolate.
- Subsequent imports can be reviewed against a working baseline.
- The migration remains controlled and portfolio-friendly.
