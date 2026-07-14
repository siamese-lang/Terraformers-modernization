# ADR-0011: Do Not Make Terraform the Main Topic

## Status

Accepted

## Context

Terraform is part of the project infrastructure and service functionality, but making Terraform itself the main topic would distort the portfolio direction.

## Decision

Terraform is used as cloud infrastructure definition and deployment control material. It is not the standalone project thesis.

## Consequences

- The project remains about backend and cloud infrastructure operations.
- Terraform code is evaluated as part of the deployment environment, not as the whole portfolio claim.
- The repository avoids becoming a generic IaC showcase.
