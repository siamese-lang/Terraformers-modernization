# ADR-0016: Treat Runtime Diagnostic Endpoints as Internal Only

## Status

Accepted

## Context

Runtime diagnostic endpoints are useful for deployment checks but should not become public API features.

## Decision

Endpoints such as `/internal/runtime/required-config` are internal operational surfaces. They should be protected in real deployments and should return no secret values.

## Consequences

- Runtime diagnosis remains possible.
- Public API surface remains limited.
- Ingress/security configuration must account for internal-only paths.
