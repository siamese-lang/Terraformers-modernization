# ADR-0010: Keep AI Generation Quality as Non-Core Scope

## Status

Accepted

## Context

The Terraformers service includes AI-based Terraform draft generation. If emphasized incorrectly, the project can look like a code generation tool or a competitor to AI development tools.

## Decision

AI generation quality is non-core for this public modernization repository. The generated Terraform output is treated as a reviewable draft, not production-ready infrastructure code.

The core focus remains backend runtime, cloud infrastructure, deployment validation, and operations documentation.

## Consequences

- The project does not compete with AI coding tools.
- Terraform generation is explained as service functionality, not the modernization thesis.
- Backend and infrastructure work remain the primary portfolio evidence.
