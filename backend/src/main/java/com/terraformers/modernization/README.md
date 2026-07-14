# Backend Package Layout

This package is reserved for the public-safe backend modernization source.

Planned package responsibilities:

```text
api/             REST controllers and request/response contracts
application/     use cases and service orchestration
domain/          entities, domain model, repository ports
infrastructure/  AWS adapters, persistence adapters, external service clients
config/          runtime configuration and secret contract checks
web/             internal readiness and operational endpoints
```

The current baseline only includes runtime configuration inspection and readiness surface. Domain/API/AWS adapter code will be imported selectively after secret and ownership review.
