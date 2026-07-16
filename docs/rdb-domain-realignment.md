# RDB Domain Realignment

## Purpose

This document defines the backend persistence realignment for `Terraformers-modernization`.

The modernization repository must not replace the original team service domain with a smaller unrelated metadata model merely to make local smoke tests easier. The previous `rdb-refactor` repository is the primary implementation reference for the core RDB domain. Modernization work should preserve that domain where it remains valid, improve its coupling and verification weaknesses, and add new analysis/runtime capabilities as extensions.

Reference repository:

```text
siamese-lang/rdb-refactor
```

Target repository:

```text
siamese-lang/Terraformers-modernization
```

## Root cause found during AWS live validation

The current target repository combined two incompatible schema models:

1. `V20260714_001__baseline_backend_schema.sql` used numeric project IDs and ownership/file/board relationships derived from the previous RDB refactor.
2. The simplified `ProjectEntity` used a string project ID and stored upload metadata, analysis result pointers, and Terraform draft content directly on `projects`.

This was not a missing-column-only problem. The primary key type, ownership model, file model, lifecycle model, and API assumptions differed. Adding corrective columns to `projects` would have preserved the wrong model and created more migration debt.

## Canonical reuse decisions

### Reuse and modernize

The following concepts from `rdb-refactor` remain the canonical core domain:

- `users`
  - Cognito subject based identity
  - email and display name
  - role/status lifecycle
- `projects`
  - numeric `BIGINT` identity primary key
  - required owner relationship
  - name/description
  - visibility/status
  - soft-delete timestamp
- `project_files`
  - project relationship
  - parent-child file tree
  - S3 object metadata
  - original filename, content type, size, checksum
  - lifecycle timestamps
- `terraform_runs`
  - project-scoped run history and status
- `boards`, `comments`, `board_reactions`
  - authenticated author relationships
  - project/board ownership chain
  - status and soft-delete behavior
- repository query patterns and ownership/visibility checks
- Flyway-first schema management with production `ddl-auto=validate`

Reuse does not mean copying the previous controller wholesale. The previous large controllers mixed authentication, S3, Bedrock, SQS, project persistence, file persistence, and compatibility responses. Those responsibilities remain separated behind services and adapters in the modernization backend.

Improvements applied while porting:

- `Instant` is used for UTC-oriented lifecycle timestamps.
- role, status, and visibility values use enums instead of unvalidated string constants.
- services use constructor injection and explicit transactional boundaries.
- baseline migrations no longer use `CREATE TABLE IF NOT EXISTS`, which could hide drift.
- repository methods encode active/soft-delete query rules.

### Keep from the modernization repository

The following modernization capabilities are valid additions and should be integrated with the canonical core domain:

- analysis job lifecycle
- provider abstraction for local/Bedrock analysis
- SQS progress publication boundary
- OpenSearch reference retrieval boundary
- S3 upload/read service boundaries
- runtime configuration inspection
- Kubernetes/Secret/runtime contract verification
- deployment package rendering and preflight verification
- frontend compatibility adapters where they do not redefine the database model

### Replace or remove

The following designs are not canonical and are being replaced:

- string slug used as `projects.project_id`
- `ProjectMetadataService` creating projects implicitly from an upload filename
- upload, analysis result, Terraform draft, and source object metadata stored in one `projects` row
- `project_comments` as an unauthenticated parallel comment model unless a distinct business requirement is proven
- compatibility test fixtures such as `shared-architecture`, `network`, and `app` being treated as database primary keys
- migrations that attempt to make the numeric baseline table match the simplified string entity

## Target relationships

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

Recommended analysis relationship:

- `analysis_jobs.project_id` references `projects.project_id` as `BIGINT`.
- the uploaded source object is represented by `project_files.file_id` or a dedicated nullable source-file foreign key.
- externally visible request correlation remains a string field such as `correlation_id`; it is not used as the project primary key.
- generated Terraform output is represented as a project file and/or an analysis result artifact, not as the sole state of the project row.

## Transitional compatibility isolation

The simplified project metadata entity is temporarily mapped to `project_metadata_compat`, not `projects`.

This table exists only while endpoint adapters are migrated. It is not a second canonical project domain and must not receive new business logic. The removal condition is:

1. upload resolves an authenticated persisted user,
2. upload creates or selects an owner-based numeric project,
3. source and generated artifacts are stored through `project_files`,
4. analysis jobs reference the numeric project and source/result files,
5. project/public/tree/draft compatibility responses read from the canonical model.

After those conditions are met, delete `project_metadata_compat`, the simplified entity, and `ProjectMetadataService`.

## Migration policy

The AWS live-smoke database was disposable and has been removed. Before editing the migration chain, confirm that no persistent shared database depends on the current `20260714` migration history.

For the repository before a production release, use a reviewed clean baseline derived from the final entity model rather than adding compensating migrations to an internally inconsistent baseline.

Rules:

1. No duplicate Flyway versions.
2. Existing applied production migrations are never silently rewritten.
3. Pre-release disposable databases may use a clean rebaseline only after the affected environments are explicitly identified.
4. MariaDB is the schema-validation target; H2 is not sufficient for production schema compatibility.
5. CI must apply all migrations to an empty MariaDB instance and start the application with `ddl-auto=validate`.
6. `ddl-auto=update/create` is not an accepted production workaround.

## Delivery phases

### Phase 1: guardrails and audit — completed

- added Flyway duplicate-version verification
- documented the canonical reuse decisions
- stopped AWS deployment attempts while schema realignment is incomplete
- isolated cross-platform line ending noise

### Phase 2A: core domain port — completed, awaiting CI

- ported and modernized `UserEntity` and `UserRepository`
- ported the owner-based numeric project aggregate as `OwnedProjectEntity`
- ported `ProjectFileEntity` and repository query patterns
- added `ProjectDomainService` ownership/access/file registration rules
- replaced the baseline DDL with the canonical ownership/file/collaboration schema
- isolated the simplified project model in `project_metadata_compat`
- added unit tests that reject project creation without a persisted owner

### Phase 2B: authentication and upload integration — next

- add Spring Security resource-server JWT validation for Cognito-issued tokens
- resolve/create the persisted user from validated claims
- create/select a numeric owner-based project before upload storage
- persist the source object in `project_files`
- remove filename-derived project slugs from canonical persistence

### Phase 3: analysis integration

- change `analysis_jobs.project_id` to the canonical numeric project foreign key
- associate analysis jobs with source and result project files
- stop implicit project creation from upload slugs
- store generated Terraform output as a project file/result artifact

### Phase 4: collaboration integration

- reuse `boards/comments/reactions` where they satisfy the public-project comment flow
- remove `project_comments` if it is only a compatibility shortcut
- preserve frontend endpoint aliases through adapters, not duplicate persistence models

### Phase 5: MariaDB CI gate

Required order before AWS live validation:

1. Flyway migration uniqueness
2. backend unit tests
3. empty MariaDB migration
4. production-profile application context with `ddl-auto=validate`
5. repository query smoke tests
6. runtime contract verification
7. deployment package render/dry-run
8. image build
9. AWS live validation

## Completion condition

The realignment is complete only when:

- every JPA entity maps to the Flyway-created MariaDB schema
- project ownership and file relationships are preserved
- compatibility endpoints do not redefine primary keys or persistence ownership
- analysis/runtime additions are linked to the original domain instead of replacing it
- CI catches duplicate migration versions and entity/schema drift before an AWS deployment is attempted
