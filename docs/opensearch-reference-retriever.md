# OpenSearch Reference Retriever

## 1. Purpose

This document explains the OpenSearch/AOSS reference retrieval boundary used by the backend-owned analysis flow.

The goal is not to present OpenSearch as the main project topic. The goal is to show that the backend can separate reference retrieval failures from S3, Bedrock, SQS, and RDB failures.

## 2. Runtime modes

### Local / CI default

```text
StubEmbeddingProvider
  -> StubReferenceRetriever
```

This path does not require AWS credentials and exists so Maven tests, Docker build, API smoke, and RDB status transitions can be verified reliably.

### Production optional path

```text
BedrockEmbeddingProvider
  -> OpenSearchReferenceRetriever
      -> SignedOpenSearchHttpClient
      -> OpenSearch / AOSS k-NN query
```

This path is enabled only when runtime flags are explicitly set.

## 3. Required runtime flags

```text
BEDROCK_EMBEDDING_ENABLED=true
OPENSEARCH_RETRIEVER_ENABLED=true
OPENSEARCH_ENDPOINT=<OpenSearch or AOSS endpoint>
OPENSEARCH_SERVICE_NAME=aoss     # use es for classic Amazon OpenSearch Service domains when applicable
OPENSEARCH_TOP_K=3
INDEX_NAME=<reference index>
VECTOR_FIELD_NAME=<embedding vector field>
CONTENT_FIELD_NAME=<reference content field>
BEDROCK_EMBEDDING_MODEL_ID=<embedding model id>
```

The default value for `OPENSEARCH_SERVICE_NAME` is `aoss` because the original service used AOSS-style reference retrieval. If the deployment uses a classic Amazon OpenSearch Service domain, the service name may need to be `es`.

## 4. Backend responsibilities

`OpenSearchReferenceRetriever` is responsible for:

- building embedding input text from project/source object context;
- requesting an embedding through `EmbeddingProvider`;
- building a k-NN query body;
- sending a signed query to the configured index;
- parsing ranked reference documents;
- failing clearly when endpoint, index, vector field, content field, access policy, or timeout is wrong.

## 5. Failure classification

| Symptom | Likely layer | Check first |
|---|---|---|
| Missing model id | Bedrock embedding config | `BEDROCK_EMBEDDING_MODEL_ID` |
| HTTP 403 | IAM/AOSS access policy | IRSA/role policy and collection policy |
| HTTP 404 | Index name/path | `INDEX_NAME` and endpoint |
| Empty hits | Data/indexing quality | indexed reference docs and vector field |
| Parse failure | Response contract | `_source` field names and `CONTENT_FIELD_NAME` |
| Timeout | Network/service | VPC endpoint, route, security group, service health |

## 6. Interview explanation

```text
OpenSearch는 프로젝트의 주제가 아니라 reference retrieval boundary입니다. Python 서비스에 섞여 있던 검색 책임을 Spring Boot backend의 `ReferenceRetriever` port로 분리했고, 로컬에서는 stub으로 검증하고 운영에서는 Bedrock embedding과 SigV4 signed OpenSearch/AOSS query로 전환할 수 있게 구성했습니다. 이렇게 하면 S3 객체 접근, Bedrock 호출, OpenSearch 검색, SQS 발행 실패를 각각 다른 계층의 문제로 분리해 설명할 수 있습니다.
```
