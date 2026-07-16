# Source Reuse Plan

## 1. Goal

`Terraformers-modernization` is the operationally modernized completion of the original team project. It is not a new simplified application that only keeps similar endpoint names.

The reuse strategy has two references:

```text
Original team repositories
- AWS-Terraformers/Terraformers
- AWS-Terraformers/Infra-code

Previous RDB refactor
- siamese-lang/rdb-refactor
```

The RDB refactor is the primary reference for the backend business domain. The original repositories remain references for frontend-visible behavior, product terminology, and infrastructure intent.

The detailed persistence decision is defined in:

```text
docs/rdb-domain-realignment.md
```

## 2. Reuse-first rule

Before implementing or replacing a feature:

1. locate the corresponding implementation and contract in the original repositories and `rdb-refactor`
2. identify what is product behavior, what is business-domain persistence, and what is obsolete runtime coupling
3. reuse valid domain models, repository behavior, API contracts, and tests
4. refactor tightly coupled implementation behind smaller services and adapters
5. implement new code only where the modernization requirements are genuinely new

A smaller implementation is not automatically a better modernization. Simplification that removes ownership, relationships, lifecycle state, or auditability is a regression.

## 3. What must be reused

### Product and frontend contracts

Preserve or provide explicit compatibility adapters for established flows such as:

- architecture image upload
- project creation and lookup
- project file/tree browsing
- analysis and Terraform result access
- public project browsing
- project collaboration/comment behavior

Endpoint aliases may be retained for frontend compatibility, but they must delegate to the canonical domain model rather than introduce parallel persistence.

### Core RDB domain

Reuse and modernize the `rdb-refactor` concepts for:

- users and Cognito identity mapping
- project ownership and visibility
- project file tree and S3 metadata
- Terraform run history
- boards, comments, and reactions
- numeric identity primary keys and foreign-key relationships
- soft-delete/status patterns
- repository ownership and access queries

### Operations principles

Reuse these established operating decisions:

- production `spring.jpa.hibernate.ddl-auto=validate`
- Flyway as the canonical schema source
- environment/Secret-driven datasource values
- no emergency switch to Hibernate schema mutation
- schema and runtime verification before AWS deployment

## 4. What should be improved instead of copied

Do not copy the previous implementation mechanically where it has these weaknesses:

- large controllers combining authentication, persistence, S3, Bedrock, and SQS
- field injection
- mixed AWS SDK v1/v2 use
- duplicated dependency versions
- direct AWS client creation inside controllers
- compatibility parsing mixed into business services
- manual schema artifacts competing with Flyway as source of truth

Modernization improvements should include:

- constructor injection
- separated storage, analysis, project, collaboration, and compatibility layers
- AWS SDK v2 clients configured as beans
- typed configuration properties and runtime contract validation
- versioned MariaDB migrations
- Testcontainers-based entity/Flyway validation
- CI ordering that prevents AWS deployment when local contracts fail

## 5. Current design decisions being reversed

The previous plan intentionally replaced the original RDB domain with a smaller metadata model. That decision is no longer valid.

The following are redesign targets:

- string project slug as the database project primary key
- implicit project creation during anonymous upload
- upload metadata and Terraform draft stored directly on `projects`
- separate `project_comments` persistence introduced only for endpoint compatibility
- compatibility fixtures used as if they were persistent IDs

The target is to restore the original project domain and connect new analysis/runtime capabilities to it.

## 6. Modernization-only additions

The following remain valid new capabilities, but must extend rather than replace the original domain:

- analysis job state and provider abstraction
- Bedrock/OpenSearch/SQS adapter boundaries
- binary upload storage boundary
- runtime configuration inspection
- Kubernetes Secret/ConfigMap contract verification
- deployment package rendering and dry-run checks
- AWS evidence collection and cleanup runbooks

## 7. Verification rule

A reused or improved feature is complete only when:

1. its business-domain behavior is traceable to the original or `rdb-refactor` implementation
2. deviations are documented with a technical reason
3. JPA mappings and Flyway DDL match on MariaDB
4. compatibility adapters are tested separately from domain services
5. runtime configuration is checked before deployment
6. no real AWS apply/destroy or Kubernetes apply is required to discover repository-level mismatches
