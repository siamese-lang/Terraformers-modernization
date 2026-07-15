# Reuse-First Implementation Workflow

## 1. Purpose

This document defines the default working method for this repository.

Before adding or changing code, every task should decide what can be reused, what should be adapted, and what must be newly implemented. This prevents the project from drifting into a full rewrite every time a new feature or validation path is requested.

The rule applies to all future work, not only the current modernization PR.

## 2. Default sequence

Use this sequence before implementation:

```text
1. Identify the requested product or runtime behavior.
2. Locate existing source, docs, scripts, tests, and workflows that already address it.
3. Classify each part as reuse, adapt, reimplement, or exclude.
4. Fix the PR cutoff before writing code.
5. Implement only the selected scope.
6. Validate with the smallest relevant workflow set.
7. Stop after the validation gate passes.
```

Do not start with a blank implementation unless the audit proves there is no reusable source or the existing source is unsafe for the current boundary.

## 3. Classification rules

### 3.1 Reuse

Use existing code or contract with minimal changes when it is already aligned with the current product flow.

Typical reuse targets:

```text
endpoint names
request field names
response field aliases
frontend-visible flow
runbook commands
validated test fixtures
existing workflow structure
```

Examples in this PR:

```text
POST /api/upload
GET /api/public-projects
GET /api/project-tree/{projectId}
GET /api/getProjectComments/{projectId}
POST /api/addProjectComment
```

### 3.2 Adapt

Adapt existing source when the behavior is correct but the implementation is too coupled to the old runtime.

Typical adapt targets:

```text
controller behavior split into services
legacy response shape mapped from a new model
old UI flow rendered through a smaller read-only component
old script logic converted into a narrower validation script
```

Adaptation must document what changed and why.

### 3.3 Reimplement

Reimplement only when direct reuse would import too much scope, hidden dependency, or unvalidated runtime behavior.

Valid reasons to reimplement:

```text
old code mixes unrelated production adapters
old code requires unavailable credentials or cloud state
old code depends on deferred auth/ownership boundaries
old code exposes unsafe browser-side controls
old code makes validation too broad to debug
```

Reimplementation should still preserve the selected product contract unless the contract is explicitly excluded.

### 3.4 Exclude

Exclude behavior when it is real but outside the current PR boundary.

Exclusions must be explicit, especially when the behavior exists in the original source. Otherwise, later work may incorrectly treat it as a missing feature to add immediately.

## 4. Pre-implementation checklist

Before changing code, answer these questions in the PR, issue, or a short docs update:

```text
1. What original or existing files are relevant?
2. Which endpoints, fields, or user flows must be preserved?
3. Which code can be reused directly?
4. Which code should be adapted into a smaller boundary?
5. Which code should be reimplemented because direct reuse is unsafe or too broad?
6. Which related features are intentionally excluded?
7. What is the smallest validation gate for this change?
8. What is the cutoff condition after which no more scope should be added?
```

If these answers are unclear, do not expand the implementation. Narrow the task first.

## 5. PR planning template

Use this template for future PRs:

```markdown
## Reuse-first plan

### Existing source reviewed

- `path/to/source`
- `path/to/test`
- `path/to/workflow`

### Reuse as-is

- ...

### Adapt

- ...

### Reimplement

- ...

### Exclude from this PR

- ...

### Validation gate

- ...

### Stop condition

- After the validation gate passes, mark the PR ready or merge it. Do not add adjacent features to the same branch.
```

## 6. Validation rule

Validation should match the selected boundary.

Examples:

| Change type | Preferred validation |
|---|---|
| frontend import or component wiring | Frontend Import Verification |
| backend contract or service behavior | Backend Local Verification |
| runtime contract scripts/manifests | Runtime Contract Verification |
| one production adapter | one manual adapter workflow |

Do not enable multiple production adapters in one PR unless the explicit goal is integration across those adapters.

## 7. Stop rule

After the selected validation gate passes:

```text
stop implementing
mark ready or merge
open a new branch for the next adapter or product surface
```

This prevents a verified branch from becoming unstable because adjacent features were added after the fact.

## 8. Portfolio explanation

```text
작업을 진행할 때 원본 또는 기존 구현을 먼저 확인하고, 그대로 재사용할 계약과 새로 분리해야 할 경계를 구분했습니다. endpoint 명칭과 사용자 흐름처럼 제품 정체성을 이루는 부분은 유지하고, 인증·S3·Bedrock·SQS·Terraform 실행처럼 결합도가 큰 런타임 로직은 한 번에 복원하지 않고 검증 가능한 단위로 분리했습니다. 이 방식은 단순 재개발이 아니라 기존 프로젝트를 운영 가능한 계약 중심으로 정리한 작업임을 설명하기 위한 기준입니다.
```
