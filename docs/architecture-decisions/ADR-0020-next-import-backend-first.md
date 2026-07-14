# ADR-0020: Import Backend Code Before Infrastructure Code

## Status

Accepted

## Context

Both backend and infrastructure are important, but infrastructure should support a clear backend runtime need.

## Decision

After baseline validation, import backend domain/API/AWS adapter code before importing full Terraform infrastructure.

## Consequences

- Infrastructure import can be shaped around actual backend runtime dependencies.
- The repository remains backend-led.
- Terraform code will be easier to explain as deployment support rather than the main project.
