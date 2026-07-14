# Runbooks

## 1. Purpose

This directory contains operational runbooks for the Terraformers backend and cloud infrastructure modernization project.

The runbooks are written to support three goals:

- verify that the deployed service behaves as expected;
- isolate failures by runtime boundary rather than guessing;
- collect portfolio evidence without exposing secrets.

## 2. Available runbooks

| Runbook | Scope |
| --- | --- |
| [`backend-analysis-adapter-failures.md`](backend-analysis-adapter-failures.md) | Backend-owned analysis job flow: RDB state, S3 source read, S3 result write, Bedrock generation, Bedrock embedding, OpenSearch/AOSS retrieval, and SQS progress publishing. |

## 3. Recommended validation order

```text
1. Run Maven tests.
2. Run backend with local/CI-safe stub adapters.
3. Execute scripts/smoke/create-analysis-job.sh.
4. Confirm SUCCEEDED, resultObjectKey, and resultPreview.
5. Enable one production adapter at a time.
6. Record request/response/log evidence with secret values removed.
```

## 4. Evidence hygiene

Do not commit:

- AWS credentials;
- access tokens;
- account IDs;
- raw secret values;
- kubeconfig files;
- tfstate/tfvars files;
- private object contents;
- full production logs containing identifiers.

Commit only sanitized command output, summaries, screenshots, or redacted evidence templates.
