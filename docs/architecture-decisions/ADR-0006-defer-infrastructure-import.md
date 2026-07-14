# ADR-0006: Defer Infrastructure Import Until Backend Baseline Validation

## Status

Accepted

## Context

The project needs both backend and cloud infrastructure code. Importing infrastructure before the backend baseline is verified can make the repository look like a Terraform showcase and may hide backend readiness issues.

## Decision

Validate the public backend baseline first. Then import Terraform modules, Kubernetes manifests, image publish workflows, and Terraform plan/apply workflows in a controlled sequence.

## Consequences

- The repository remains backend-led instead of Terraform-led.
- Infrastructure import will be easier to validate against actual backend runtime needs.
- Terraform code must remain secret-free and validate with `terraform init -backend=false` before remote backend use.
