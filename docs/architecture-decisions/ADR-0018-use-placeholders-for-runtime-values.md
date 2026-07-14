# ADR-0018: Use Placeholders for Runtime Values

## Status

Accepted

## Context

Public repositories must not contain real runtime secrets or account-specific values.

## Decision

Use placeholders in example files and documentation. Real values must be delivered through runtime configuration mechanisms such as environment variables, GitHub Secrets/Variables, Kubernetes Secrets, External Secrets, or AWS Secrets Manager.

## Consequences

- Public examples remain safe to share.
- Deployment requires explicit environment configuration.
- Documentation must distinguish placeholders from real runtime values.
