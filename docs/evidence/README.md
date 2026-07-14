# Evidence

This directory is reserved for sanitized validation evidence.

## Rules

- Do not commit raw logs containing tokens, passwords, private account ids, ARNs, or endpoint values.
- Prefer templates and redacted examples.
- Distinguish between code-level validation, CI validation, and actual AWS deployment validation.

## Planned evidence categories

```text
docs/evidence/
  backend-build.md
  backend-runtime.md
  terraform-validate.md
  image-tag-consistency.md
  smoke-test.md
```

## Current state

At this stage, the repository contains a backend public baseline and CI workflow definitions. Actual GitHub Actions run results and AWS deployment evidence should be added only after they are verified and sanitized.
