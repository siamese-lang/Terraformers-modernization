# ADR-0002: Focus on Backend and Cloud Infrastructure Modernization

## Status

Accepted

## Context

Terraformers includes frontend, AI generation, backend, and cloud infrastructure concerns. For portfolio positioning, the project can easily drift into an AI code generation project, frontend project, or Terraform platform project.

The intended portfolio message is backend development and cloud infrastructure operation.

## Decision

The modernization scope will focus on:

- Spring Boot backend structure
- RDB/Flyway schema consistency
- S3/SQS/Cognito/Secrets Manager integration boundaries
- Docker image build and runtime configuration
- Terraform infrastructure organization
- GitHub Actions verification and deployment control
- smoke tests, evidence, and runbooks

Frontend and AI generation quality work will remain non-core unless needed for backend/API validation.

## Consequences

- The repository better supports backend/cloud infrastructure job applications.
- Frontend and AI model quality claims remain limited.
- Future code import must be evaluated against backend/cloud infrastructure relevance.
