# ADR-0021: Add Full API Smoke Tests After API Import

## Status

Accepted

## Context

The current backend baseline does not yet include the full original Terraformers API implementation.

## Decision

Keep current smoke evidence limited to health and runtime configuration checks. Add full API smoke tests only after project/file/comment/SQS API code is imported and reviewed.

## Consequences

- Smoke tests do not pretend unavailable APIs exist.
- Future validation can grow with actual backend code.
- Evidence remains aligned with repository contents.
