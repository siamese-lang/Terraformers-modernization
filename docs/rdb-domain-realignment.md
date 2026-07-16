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

The current target repository combines two incompatible schema models:

1. `V20260714_001__baseline_backend_schema.sql` uses numeric project IDs and ownership/file/board relationships derived from the previous RDB refactor.
2. The current `ProjectEntity` uses a string project ID and stores upload metadata, analysis result pointers, and Terraform draft content directly on `projects`.

This is not a missing-column-only problem. The primary key type, ownership model, file model, lifecycle model, and API assumptions differ. Adding corrective columns to the current `projects` table would preserve the wrong model and create more migration debt.

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

Reuse does not mean copying the previous controller wholesale. The previous large controllers mixed authentication, S3, Bedrock, SQS, project persistence, file persistence, and compatibility responses. Those responsibilities must remain separated behind services and adapters in the modernization backend.

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

The following current designs are not canonical and should be replaced:

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

## Migration policy

The AWS live-smoke database was disposable and has been removed. Before editing the migration chain, confirm that no persistent shared database depends on the current `20260714` migration history.

For the repository before a production release, prefer a reviewed clean baseline derived from the final entity model rather than adding many compensating migrations to an internally inconsistent baseline.

Rules:

1. No duplicate Flyway versions.
2. Existing applied production migrations are never silently rewritten.
3. Pre-release disposable databases may use a clean rebaseline only after the affected environments are explicitly identified.
4. MariaDB is the schema-validation target; H2 is not sufficient for production schema compatibility.
5. CI must apply all migrations to an empty MariaDB instance and start the application with `ddl-auto=validate`.
6. `ddl-auto=update/create` is not an accepted production workaround.

## Delivery phases

### Phase 1: guardrails and audit

- add Flyway duplicate-version verification
- document the canonical reuse decisions
- stop AWS deployment attempts while schema realignment is incomplete
- inventory current API contracts and classify them as canonical, compatibility-only, or removable

### Phase 2: core domain port

- port and modernize `UserEntity`, `ProjectEntity`, and `ProjectFileEntity`
- port repositories and ownership/visibility service logic
- keep packages and constructor injection consistent with the modernization codebase
- avoid copying obsolete AWS SDK v1, controller field injection, and dependency duplication

### Phase 3: analysis integration

- change `analysis_jobs.project_id` to the canonical numeric project foreign key
- associate analysis jobs with source and result project files
- stop implicit project creation from upload slugs
- define authenticated project creation/upload behavior

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
