# ADR-0009: Keep Frontend as a Non-Core Validation Surface

## Status

Accepted

## Context

Terraformers includes a frontend, but the public modernization project is intended to show backend development and cloud infrastructure management.

## Decision

Frontend work is non-core. It should be used only as a client surface for E2E validation unless a minimal adjustment is necessary for backend/API verification.

## Consequences

- The portfolio message remains backend/cloud infrastructure focused.
- Frontend implementation is not overstated as a personal contribution.
- API and runtime validation remain the main evidence path.
