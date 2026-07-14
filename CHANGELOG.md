# Changelog

## 2026-07-14

### Added

- Public repository direction documents.
- Backend and cloud infrastructure modernization scope.
- Public-safe Spring Boot backend baseline.
- Backend Maven and Docker build workflows.
- Runtime config contract and internal readiness surface.
- Flyway baseline schema for backend modernization track.
- Local backend verification script.
- Evidence templates for backend build, runtime check, Terraform validation, image tag consistency, and smoke tests.

### Notes

- The backend baseline is not yet the full original Terraformers backend implementation.
- Private repository history, real secrets, tfstate, tfvars, kubeconfig, and account-specific values are intentionally excluded.
