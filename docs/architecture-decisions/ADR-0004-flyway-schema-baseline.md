# ADR-0004: Use Flyway as the Backend Schema Baseline

## Status

Accepted

## Context

The modernization project needs to explain database schema consistency as part of backend operations. Relying on automatic schema creation hides schema drift and weakens the operational story.

## Decision

Use Flyway migration files as the canonical schema change path for the public backend modernization track.

Use Hibernate `ddl-auto=validate` in production runtime to detect schema drift rather than silently modifying schema.

## Consequences

- Schema changes are explicit and reviewable.
- Startup failures caused by schema mismatch can be explained and diagnosed.
- Manual hotfix SQL must be treated as emergency recovery material, not the standard schema path.
