# RDB Domain Realignment

## Purpose

`Terraformers-modernization` is the operationally modernized completion of the original team service. It must extend the original business domain rather than replace it with a smaller metadata-only application.

Canonical implementation reference:

```text
siamese-lang/rdb-refactor
```

Modernization target:

```text
siamese-lang/Terraformers-modernization
```

## Root cause

The repository previously combined two incompatible project models:

1. Flyway created numeric owner-based projects with project/file/collaboration relationships.
2. The simplified JPA model used a string slug as the project primary key and stored upload metadata, analysis pointers, and Terraform draft content directly on the project row.

This was not a missing-column problem. Primary-key type, ownership, file lifecycle, authorization, and API assumptions all differed. Adding compensating columns would have preserved the wrong model.

## Canonical domain

The modernization backend now uses this relationship model:

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

### Reused from `rdb-refactor`

- Cognito-subject user identity
- numeric `BIGINT` project identity
- required project owner
- visibility, status, and soft-delete lifecycle
- hierarchical project files with object-storage metadata
- project-scoped Terraform run history
- authenticated boards, comments, and reactions
- repository ownership and active-record query rules
- Flyway-first schema management and production `ddl-auto=validate`

### Improved while porting

- `Instant` lifecycle timestamps
- typed enums for role/status/visibility
- constructor injection and explicit transactions
- Spring Security OAuth2 resource-server JWT verification
- Cognito access-token `sub` as the required identity claim
- optional email/display-name profile data
- separated authentication, project, storage, analysis, artifact, and compatibility responsibilities
- no `CREATE TABLE IF NOT EXISTS` in the clean pre-release baseline
- MariaDB schema validation before any AWS deployment

## Final upload and analysis flow

```text
Cognito access token
  -> JWT signature / issuer / client validation
  -> persisted user resolution by sub
  -> create private numeric project or authorize existing owner/admin project
  -> store architecture image through the upload boundary
  -> register source metadata in project_files
  -> create analysis_jobs(project_id, source_file_id)
  -> run analysis provider
  -> write generated main.tf through ObjectWriter
  -> register full Terraform content and object metadata in project_files
  -> set analysis_jobs.result_file_id
```

Client-provided filenames and correlation IDs are never used as database project primary keys. Direct analysis creation derives bucket/key from the persisted source file instead of trusting independent client values.

## Artifact model

`project_files` is the source of truth for both source and generated artifacts.

### Architecture image

```text
file_type        = ARCHITECTURE_IMAGE
path             = source/<original filename>
storage_provider = metadata-only | s3
binary_persisted = true | false
s3_bucket / s3_key / storage_etag
content_type / size_bytes
```

### Generated Terraform

```text
file_type        = GENERATED_TERRAFORM
path             = terraform/main.tf
inline_content   = full editable Terraform content
checksum         = SHA-256
size_bytes       = UTF-8 byte length
s3_bucket / s3_key / storage_etag
```

A new analysis result soft-deletes the previous active generated Terraform artifact. Editing `main.tf` updates the canonical artifact and writes through the configured object-storage boundary.

## API compatibility policy

Frontend-visible endpoint names are preserved where useful, but all identifiers and authorization rules now delegate to the canonical domain.

Examples:

```text
POST /api/upload
GET  /api/projects/{numericProjectId}
GET  /api/project-tree/{numericProjectId}
GET  /api/projects/{numericProjectId}/terraform/main.tf
GET  /api/public-projects
GET  /api/getProjectComments/{numericProjectId}
POST /api/addProjectComment
```

Compatibility endpoints no longer define a second persistence model.

## Collaboration flow

The parallel `project_comments` table and unauthenticated author field were removed.

Public project comments now use:

```text
projects
  -> boards(category=PUBLIC_DISCUSSION)
       -> comments(writer_user_id)
```

- public comment listing remains anonymous-readable
- comment creation requires an authenticated Cognito user
- request `userEmail` is retained only as a compatibility input and is not trusted as author identity
- response author data comes from the persisted authenticated user
- private project comments are rejected

## Removed designs

- string project slug primary key
- `ProjectEntity` and `ProjectRepository` compatibility aggregate
- `project_metadata_compat`
- implicit anonymous project creation
- project row containing source upload and Terraform draft state
- `ProjectCommentEntity`, `ProjectCommentRepository`, and `project_comments`
- client-controlled comment author identity
- unauthenticated analysis job polling

## Migration policy

The current migration chain is a reviewed clean pre-release baseline. It is valid only because the previous AWS live-smoke database was disposable and removed.

Rules:

1. No duplicate Flyway versions.
2. An applied production migration must never be silently rewritten.
3. MariaDB is the schema-validation target; H2 alone is insufficient.
4. Production remains `spring.jpa.hibernate.ddl-auto=validate`.
5. `ddl-auto=update/create` is not an accepted workaround.
6. Repository/schema validation must pass before AWS or Kubernetes deployment work resumes.

## Verification gates

`Backend Local Verification` contains two independent jobs.

### Backend local verification

- Flyway migration-version uniqueness
- Maven clean test
- Spring Security/JPA context creation
- authenticated upload and polling
- numeric project/source/result file contracts
- canonical project metadata/tree/draft/source-object adapters
- authenticated board/comment compatibility adapters

### MariaDB Flyway and Hibernate validation

- MariaDB 11.4 service
- package backend
- start production profile
- apply Flyway migrations to an empty database
- start Hibernate with `ddl-auto=validate`
- require actuator health success
- upload startup logs on failure

## Remaining pre-deployment sequence

1. pass both Backend Local Verification jobs
2. fix any actual MariaDB/Flyway/JPA mismatch
3. add focused repository-query smoke assertions if needed
4. run runtime contract verification
5. render and dry-run deployment packages
6. build application images
7. only then reconsider AWS live validation

## Completion condition

The RDB realignment is complete when:

- backend tests pass against the canonical model
- Flyway creates an empty MariaDB schema successfully
- the production profile starts with `ddl-auto=validate`
- no JPA entity references removed compatibility tables
- project ownership and file relationships are enforced
- compatibility endpoints do not redefine primary keys or author identity
- analysis and collaboration features extend the original domain rather than replacing it
