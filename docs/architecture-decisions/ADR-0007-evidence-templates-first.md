# ADR-0007: Add Evidence Templates Before Real Evidence

## Status

Accepted

## Context

Portfolio evidence is useful only if it is safe to share and clearly separates verified results from planned validation.

## Decision

Add evidence templates before committing real command output or screenshots.

Real evidence must be sanitized and must distinguish:

- code-level validation
- CI validation
- actual AWS deployment validation

## Consequences

- Evidence collection has a consistent structure.
- Secret and account-specific leakage risk is reduced.
- The repository avoids claiming deployment completion before verification exists.
