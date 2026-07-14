# ADR-0013: Keep a Clean Public History

## Status

Accepted

## Context

A public portfolio repository should be easy to review and safe to share. Copying private history can expose noise, secrets, or misleading authorship context.

## Decision

Keep the public repository history clean. Add reviewed files intentionally instead of importing private Git history.

## Consequences

- Reviewers see a focused modernization repository.
- Some original context must be documented instead of preserved as commit history.
- Future imports require explicit review and documentation updates.
