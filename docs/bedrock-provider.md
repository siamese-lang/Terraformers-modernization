# Bedrock Provider Integration

## 1. Purpose

This document explains how the Spring Boot backend integrates the Bedrock vision model without keeping the original Python Flask service as a required runtime.

The implementation is intentionally feature-flagged. Local and CI verification use the stub provider by default. Bedrock is enabled only in a deployment environment with AWS runtime identity and required configuration.

## 2. Runtime switch

Default behavior:

```yaml
terraformers:
  analysis:
    bedrock-provider-enabled: false
```

Production Bedrock path:

```bash
BEDROCK_PROVIDER_ENABLED=true
S3_READER_ENABLED=true
BEDROCK_MODEL_ID=<bedrock-model-id>
BEDROCK_MAX_TOKENS=4096
```

When `BEDROCK_PROVIDER_ENABLED=false`, `StubAnalysisProvider` remains active and no AWS model call is made.

When `BEDROCK_PROVIDER_ENABLED=true`, `BedrockAnalysisProvider` becomes the `AnalysisProvider` implementation.

## 3. Request flow

```text
AnalysisJobOrchestrator
  -> BedrockAnalysisProvider
      -> ObjectReader.readContent(bucket/key)
      -> ReferenceRetriever.retrieve(query)
      -> BedrockPromptBuilder.buildClaudeVisionRequest(...)
      -> BedrockRuntimeClient.invokeModel(...)
      -> BedrockResponseParser.extractText(...)
  -> AnalysisResult(terraformCode, explanation, references)
```

## 4. Implementation components

- `BedrockAnalysisProvider`
  - feature-flagged provider implementation
  - owns Bedrock Runtime invocation
  - does not log image bytes, prompt body, or generated secret values

- `BedrockPromptBuilder`
  - builds the Anthropic Claude vision request body
  - embeds the uploaded image as base64
  - includes sanitized object metadata and reference documents
  - rejects unsupported content types before model invocation

- `BedrockResponseParser`
  - extracts returned text from the Bedrock response body
  - strips markdown code fences if the model returns them

## 5. Operational checks

Before enabling Bedrock provider in a deployed environment, verify:

```text
[ ] backend pod has AWS runtime identity through IRSA or equivalent role
[ ] role can invoke the selected Bedrock model
[ ] S3_READER_ENABLED=true and source object can be read
[ ] BEDROCK_PROVIDER_ENABLED=true
[ ] BEDROCK_MODEL_ID is set
[ ] model region matches backend AWS region
[ ] request/response bodies are not logged
[ ] failure path marks analysis_jobs.status=FAILED
```

## 6. Failure classification

| Symptom | Likely layer | Check |
|---|---|---|
| Unsupported image content type | backend validation | object metadata and extension |
| Access denied when reading source object | S3/IAM | pod role, bucket policy, object key |
| Bedrock model access denied | IAM/Bedrock | role permission, model access, region |
| Bedrock timeout | model/runtime | timeout, payload size, retry policy |
| Empty model response | Bedrock/parser | response body, parser assumptions |
| job remains RUNNING | backend lifecycle | exception handling, transaction boundary |

## 7. Portfolio explanation

```text
원본 Python 분석 서비스가 담당하던 Bedrock 호출을 Spring Boot backend의 AnalysisProvider port 뒤로 옮겼습니다. 기본값은 stub provider라서 CI와 로컬 검증은 AWS credential 없이 가능하고, 운영 환경에서는 BEDROCK_PROVIDER_ENABLED와 S3_READER_ENABLED를 켜서 같은 backend lifecycle 안에서 S3 객체 조회, reference retrieval, Bedrock 호출, 결과 파싱까지 수행하도록 했습니다.
```
