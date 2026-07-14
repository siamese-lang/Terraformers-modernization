# ADR-0005: Expose Only Runtime Config Key Presence

## Status

Accepted

## Context

Deployment failures often come from missing runtime configuration rather than application logic. However, exposing actual secret values is unsafe.

## Decision

Provide an internal readiness surface that reports required runtime key names and boolean presence only.

The endpoint must not return passwords, tokens, endpoint secrets, or raw configuration values.

## Consequences

- Operators can distinguish missing configuration from code failures.
- The endpoint remains safer for diagnostics.
- Real deployments must still protect internal endpoints through network, ingress, or authentication controls.
