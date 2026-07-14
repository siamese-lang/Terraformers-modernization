# ADR-0008: Reserve Clean Backend Package Boundaries

## Status

Accepted

## Context

The original team project backend code may have package names and module boundaries that reflect the short project timeline. The public modernization repository should make backend responsibility boundaries easier to explain.

## Decision

Use the following public package boundaries as the target structure:

```text
api/             REST controllers and request/response contracts
application/     use cases and service orchestration
domain/          entities, domain model, repository ports
infrastructure/  AWS adapters, persistence adapters, external service clients
config/          runtime configuration and secret contract checks
web/             internal readiness and operational endpoints
```

## Consequences

- Future imports can be organized by responsibility.
- Backend modernization can be explained without claiming full rewrite ownership.
- Some original paths may be changed during public-safe import.
