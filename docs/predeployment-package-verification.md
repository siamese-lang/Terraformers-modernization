# Pre-deployment Package Verification

## Purpose

This gate proves that the modernized service can be packaged and started without publishing an image or changing a cluster.

It verifies three delivery units:

1. the React production bundle
2. the Spring Boot backend runtime image
3. the Kubernetes base, local-stub, and AWS runtime-template packages

## Safety boundary

The workflow does not perform any of the following:

- `docker push`
- AWS authentication or resource creation
- Terraform apply/destroy
- Kubernetes apply against a cluster
- External Secrets installation
- Bedrock, OpenSearch, SQS, or S3 production-adapter enablement

Kubernetes resources are rendered and passed only through client-side dry-run parsing.

## Runtime contract

The base production contract requires:

- MariaDB datasource URL, username, and password
- Cognito region, user pool, app client, and JWK URL
- upload/result bucket naming

Optional adapter settings are required only when their switches are enabled:

- `BEDROCK_PROVIDER_ENABLED` -> `BEDROCK_MODEL_ID`
- `BEDROCK_EMBEDDING_ENABLED` -> `BEDROCK_EMBEDDING_MODEL_ID`
- `OPENSEARCH_RETRIEVER_ENABLED` -> endpoint, index, vector field, and content field
- `ANALYSIS_SQS_PUBLISHER_ENABLED` -> progress and result queue URLs

The production startup validator rejects an enabled adapter whose own settings are missing. Disabled adapters do not require placeholder secrets.

## Image verification

The workflow builds `backend/Dockerfile` with two local tags:

```text
terraformers-backend:predeployment
terraformers-backend:local-stub
```

The image must:

- declare the non-root `appuser`/UID `10001`
- contain the packaged application JAR
- contain the pinned Terraform CLI
- expose a container healthcheck
- start with the local profile and disabled external adapters
- return a successful Actuator health response

No image is pushed to a registry.

## Kubernetes package verification

The workflow renders:

```text
infra/kubernetes/base
infra/kubernetes/overlays/local-stub
infra/kubernetes/overlays/aws-runtime-template
```

Each rendered package must:

- parse through `kubectl create --dry-run=client`
- contain no committed Secret resource
- enforce non-root execution
- block privilege escalation
- include a startup probe

The local overlay must reference `terraformers-backend:local-stub` with `imagePullPolicy: Never`.

The AWS template must keep an explicit immutable image replacement contract and must never use `latest`.

## Evidence

The workflow uploads `artifacts/predeployment` containing:

- frontend build file list
- backend image inspect and layer history
- image healthcheck metadata
- runtime UID and Terraform version
- backend health response and container log
- rendered Kubernetes packages
- verification summary

These files are validation evidence, not proof that an AWS deployment occurred.
