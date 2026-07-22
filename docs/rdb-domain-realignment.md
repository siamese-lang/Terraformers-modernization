# RDB Domain Realignment

## Purpose

`Terraformers-modernization` completes the original team service as a container-based cloud web service. It reuses the owner-based RDB domain from `siamese-lang/rdb-refactor` instead of replacing it with a metadata-only application.

## Corrected root cause

The repository previously combined two incompatible project models:

1. Flyway defined numeric owner-based projects and project/file/collaboration relations.
2. The simplified JPA layer used a string slug as the project primary key and stored upload, analysis, and Terraform draft state directly on the project row.

This was a primary-key, ownership, lifecycle, authorization, and API-contract conflict—not a missing-column problem.

## Canonical domain

```text
users
  └─ projects
       ├─ project_files
       ├─ analysis_jobs
       ├─ terraform_runs
       └─ boards
            ├─ comments
            └─ board_reactions
```

Reused from `rdb-refactor`:

- Cognito-subject user identity
- numeric `BIGINT` project identity
- required project owner
- visibility, status, and soft-delete lifecycle
- hierarchical project files with storage metadata
- authenticated boards, comments, and reactions
- ownership and active-record repository queries
- Flyway-first migrations and production `ddl-auto=validate`

Improved while porting:

- Spring Security OAuth2 resource-server JWT validation
- Cognito access-token `sub` as the required identity claim
- optional email/display-name profile data
- separated authentication, domain, storage, analysis, and artifact services
- MariaDB schema and repository validation before deployment

## Final upload and analysis flow

```text
Cognito access token
  -> verify JWT signature / issuer / app client
  -> resolve persisted user by sub
  -> create private numeric project or authorize owner/admin
  -> store architecture image through the storage boundary
  -> register source metadata in project_files
  -> create analysis_jobs(project_id, source_file_id)
  -> execute analysis provider
  -> write generated main.tf through ObjectWriter
  -> register full Terraform artifact in project_files
  -> set analysis_jobs.result_file_id
```

Client filenames, bucket values, object keys, and correlation IDs never become project primary keys. Direct analysis creation derives source storage metadata from the persisted project file.

## Artifact source of truth

`project_files` stores both source and generated artifacts.

```text
ARCHITECTURE_IMAGE
  path             = source/<original filename>
  storage_provider = metadata-only | s3
  s3 metadata / content type / size

GENERATED_TERRAFORM
  path             = terraform/main.tf
  inline_content   = full editable Terraform
  checksum         = SHA-256
  size_bytes       = UTF-8 length
  object-storage metadata
```

A new analysis result soft-deletes the previous generated Terraform artifact. Editing `main.tf` updates the canonical artifact and writes through the configured storage boundary.

## Compatibility endpoint policy

Frontend-visible endpoint names remain where useful, but all IDs and authorization rules delegate to the canonical domain.

```text
POST /api/upload
GET  /api/projects/{numericProjectId}
GET  /api/project-tree/{numericProjectId}
GET  /api/projects/{numericProjectId}/terraform/main.tf
GET  /api/public-projects
GET  /api/getProjectComments/{numericProjectId}
POST /api/addProjectComment
```

Public comments use `projects -> boards -> comments -> users`. Comment author identity comes from the authenticated JWT user, not request `userEmail`.

## Removed parallel designs

- string-slug project primary key
- compatibility `ProjectEntity` / `ProjectRepository`
- `project_metadata_compat`
- implicit anonymous project creation
- project rows containing upload and Terraform draft state
- parallel `project_comments` entity/table
- client-controlled comment author identity
- unauthenticated analysis polling

## Verification result

The RDB realignment gates have passed:

- Flyway migration-version uniqueness
- complete backend test suite against the canonical local/H2 model
- authenticated upload and polling
- numeric project/source/result-file contracts
- canonical metadata/tree/draft/source/comment adapters
- MariaDB 11.4 migration on an empty database
- production startup with Hibernate `ddl-auto=validate`
- owner/public project Repository queries
- soft-deleted file filtering
- latest analysis result lookup
- board/comment foreign-key traversal
- Runtime Contract Verification for the canonical API and removed-model guards

The RDB realignment is therefore complete. The active work has moved to `docs/predeployment-package-verification.md`.

## Migration rules retained

1. No duplicate Flyway versions.
2. An applied production migration must never be rewritten.
3. MariaDB—not H2 alone—is the schema target.
4. Production remains `spring.jpa.hibernate.ddl-auto=validate`.
5. `ddl-auto=update/create` is not an accepted workaround.
6. Schema and Repository gates must remain green before any live deployment.
