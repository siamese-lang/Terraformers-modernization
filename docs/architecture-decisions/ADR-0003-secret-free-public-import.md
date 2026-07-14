# ADR-0003: Keep Public Imports Secret-Free and History-Free

## Status

Accepted

## Context

The original and intermediate repositories may contain private history, environment-specific settings, or deployment artifacts that should not be exposed in a public portfolio repository.

## Decision

Do not import private repository history wholesale.

Only import reviewed, public-safe files. Replace real environment values with placeholders, examples, repository variables, GitHub secrets, Kubernetes Secrets, External Secrets, or Secrets Manager references.

## Consequences

- Public repository history starts clean.
- Migration requires more manual selection work.
- The repository remains safer for portfolio sharing.
