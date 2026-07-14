# ADR-0001: Start with a Public-Safe Backend Baseline

## Status

Accepted

## Context

The previous modernization work exists in private repositories and may contain private history, account-specific values, or team project context that should not be published wholesale.

The portfolio repository must show backend and cloud infrastructure modernization without making Terraformers look like a new solo project or exposing sensitive values.

## Decision

Start the public repository with a minimal, public-safe Spring Boot backend baseline instead of copying the full private repository history.

The baseline includes:

- Maven/Spring Boot project structure
- Dockerfile
- runtime config contract
- internal readiness endpoint
- Flyway baseline schema
- Maven and Docker build workflows
- evidence templates

## Consequences

- The repository has an immediately understandable backend/cloud infrastructure direction.
- The full original Terraformers backend API is not yet present.
- Future imports must be selective and reviewed for secrets, ownership, and project-direction fit.
