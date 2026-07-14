# Reference Retrieval

## 1. Purpose

Reference retrieval is the backend boundary that replaces the OpenSearch query portion of the original Python analysis service.

The purpose is not to treat OpenSearch as the core project topic. The purpose is to make the backend analysis flow explicit:

```text
source object metadata
  -> image / service analysis text
  -> embedding query
  -> OpenSearch/AOSS reference search
  -> ranked reference documents
  -> Terraform draft generation
```

## 2. Current implementation

The public baseline currently uses `StubReferenceRetriever`.

This stub returns deterministic reference documents so that the following can be tested without AWS credentials:

- Maven compile/test
- analysis provider wiring
- API response behavior
- RDB analysis job state transition
- local smoke scripts

## 3. Target production implementation

A production implementation behind `ReferenceRetriever` should do the following:

1. Build a reference query from image analysis text, detected AWS service names, or project context.
2. Invoke the Bedrock embedding model.
3. Query OpenSearch/AOSS with the configured index and vector field.
4. Return ranked reference documents to the `AnalysisProvider`.
5. Fail with classified errors when index, field, IAM permission, endpoint, or timeout problems occur.

## 4. Runtime configuration

The implementation must use runtime configuration, not hardcoded values.

Required values:

- `BEDROCK_EMBEDDING_MODEL_ID`
- `OPENSEARCH_ENDPOINT`
- `INDEX_NAME`
- `VECTOR_FIELD_NAME`
- `CONTENT_FIELD_NAME`
- AWS region and runtime identity

These values are provided through `application-prod.yml`, environment variables, and the Secret/runtime config delivery mechanism described in the deployment documents.

## 5. Failure classification

OpenSearch/AOSS failures should be classified separately from Bedrock and S3 failures.

Recommended categories:

| Failure | Likely check |
|---|---|
| endpoint missing | runtime config / Secret sync |
| access denied | IAM role / IRSA / policy |
| index missing | OpenSearch bootstrap / Terraform output |
| vector field mismatch | index mapping / `VECTOR_FIELD_NAME` |
| timeout | network path / OpenSearch health / query size |
| empty result | reference data ingestion / embedding mismatch |

## 6. Portfolio explanation

```text
Python 서비스가 담당하던 OpenSearch 검색을 별도 런타임으로 유지하지 않고, Spring Boot backend의 ReferenceRetriever port로 분리했습니다. 현재는 로컬/CI 검증 가능한 stub 구현을 두고, 운영 구현에서는 Bedrock embedding과 OpenSearch/AOSS k-NN 검색을 붙일 수 있도록 runtime config와 failure boundary를 문서화했습니다.
```
