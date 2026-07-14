# ADR 0004: Consolidate analysis orchestration into the backend

## Status

Accepted.

## Context

The original Terraformers implementation separated part of the backend flow into a Python Flask service. That Python service receives `/analyze` requests, reads an uploaded image from S3, detects the image media type, invokes Bedrock, retrieves reference documents from OpenSearch, and publishes progress/result messages to SQS.

Those responsibilities are important to the service, but they are not inherently Python-specific. They are mostly AWS SDK calls, request orchestration, runtime configuration, and queue/message handling.

The current portfolio direction is not AI model quality improvement. The direction is backend development and cloud infrastructure construction/management. Therefore, keeping a second Python runtime must be justified by a clear technical need.

## Decision

The target architecture will treat the Spring Boot backend as the owner of the analysis orchestration flow.

The Python service will not be imported as a required runtime component for the public modernization baseline.

Instead, the backend will expose and own the analysis job lifecycle:

```text
API request
  -> backend validates user/project/file context
  -> backend records analysis job state in RDB
  -> backend reads object metadata from S3/RDB
  -> backend invokes analysis provider
  -> backend publishes progress/result messages to SQS
  -> backend stores result metadata and job status
```

The Python implementation may remain only as a legacy reference while the Java backend migration is completed.

## Rationale

### 1. Python is not required for the current responsibilities

The observed Python service mainly performs the following operations:

- Flask HTTP endpoint handling
- S3 object read
- image media type detection
- Bedrock Runtime invocation
- embedding request
- OpenSearch vector query
- SQS progress/result message publish
- runtime environment validation

These can be implemented in Java/Spring Boot with AWS SDK and standard backend libraries.

### 2. A second runtime increases operations complexity

Keeping Python as a required runtime means the project must manage:

- second Dockerfile
- second image build/publish workflow
- second Kubernetes Deployment/Service
- second runtime Secret contract
- second health check surface
- backend-to-worker HTTP error handling
- duplicate AWS SDK credential handling
- independent logging and tracing behavior

That complexity is only worth keeping if Python provides material value. For the current portfolio goal, it weakens the backend-centered story.

### 3. Backend ownership is easier to explain in interviews

A backend-centered analysis flow shows:

- domain state management
- RDB job lifecycle
- external dependency adapters
- S3/SQS/Bedrock/OpenSearch integration
- runtime config and Secret handling
- failure classification
- smoke test and runbook structure

This is more aligned with backend development and cloud infrastructure roles than maintaining a separate Flask worker without a strong reason.

## Consequences

### Positive

- Backend responsibility becomes clearer.
- Infrastructure is simpler: one core backend runtime instead of backend + Python worker.
- Runtime config and Secret handling can be centralized.
- RDB job state, SQS result flow, and API behavior are easier to test.
- The public repository no longer needs to expose or maintain a Python service unless a later requirement justifies it.

### Negative / Trade-offs

- Existing Python prompt and OpenSearch code must be migrated or reimplemented.
- If future image preprocessing requires Python-only libraries, the decision may need to be revisited.
- Long-running Bedrock calls must be carefully handled with timeout, retry, and async job state in the backend.

## Implementation plan

1. Add backend analysis job domain model.
2. Add RDB table for analysis job lifecycle.
3. Add backend API for creating and checking analysis jobs.
4. Add runtime config contract for integrated Bedrock/OpenSearch mode.
5. Keep Python service as legacy reference only, not as default deployment target.
6. Remove Python service from core deployment documentation after the Java path is implemented.

## Decision boundary

Python may be reintroduced only if at least one of the following becomes true:

- image preprocessing requires Python-only libraries that are not practical in Java;
- the analysis workload must scale independently from the backend because of measurable runtime pressure;
- a separate worker architecture is implemented with queue-based async processing rather than a simple HTTP Flask side service;
- there is a concrete production-grade reason to split the runtime.

Until then, the default modernization direction is **integrated Spring Boot backend orchestration**.
