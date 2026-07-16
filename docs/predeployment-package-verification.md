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

Kubernetes resources are rendered and structurally checked without contacting a Kubernetes API server.

## Runtime contract

The base production contract requires:

- MariaDB datasource URL, username, and password
- Cognito region, user pool, app client, and JWK URL
- `S3_BUCKET_NAME`

Optional adapter settings are required only when their switches are enabled:

- `BEDROCK_PROVIDER_ENABLED` -> `BEDROCK_MODEL_ID`
- `BEDROCK_EMBEDDING_ENABLED` -> `BEDROCK_EMBEDDING_MODEL_ID`
- `OPENSEARCH_RETRIEVER_ENABLED` -> endpoint, index, vector field, and content field
- `ANALYSIS_SQS_PUBLISHER_ENABLED` -> progress and result queue URLs

The production startup validator rejects an enabled adapter whose own settings are missing. Disabled adapters do not require placeholder secrets.

## Frontend dependency gate

`frontend/package-lock.json` is a committed delivery input. The package job does not generate or repair dependency resolution in CI. A missing lockfile is a verification failure.

The gate runs this deterministic sequence:

```text
committed package-lock.json presence check
AJV root compatibility checks
npm ci
AJV runtime module-resolution checks
npm run build
```

`actions/setup-node` uses `frontend/package-lock.json` as the npm cache dependency path. Cache restoration can improve execution time, but dependency installation remains `npm ci` against the committed lockfile.

CRA 5 includes loaders from multiple AJV generations. The root build dependency is pinned to `ajv@8.20.0` with `ajv-keywords@5.1.0`, while older AJV 6 copies remain nested for legacy loaders. The gate records the committed lockfile, root resolution, runtime module path, and full AJV dependency tree.

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

`kubectl create --dry-run=client` is not used as the offline gate. Even with validation disabled, the command can invoke API discovery and contact the current kubeconfig server. Run `29478670742` demonstrated this by attempting to reach `localhost:8080` after all three Kustomize renders had already succeeded.

The cluster-free gate uses `kubectl kustomize` and verifies that each rendered package:

- is non-empty
- contains only complete YAML documents with `apiVersion`, `kind`, `metadata`, and `metadata.name`
- contains ConfigMap, ServiceAccount, Service, and Deployment resources
- contains no committed Secret resource
- enforces non-root execution
- blocks privilege escalation
- includes a startup probe

The local overlay must reference `terraformers-backend:local-stub` with `imagePullPolicy: Never`.

The AWS template must keep an explicit immutable image replacement contract and must never use `latest`.

Server-side schema admission remains a live-cluster deployment gate and is intentionally not claimed by this offline verification.

## Evidence

The workflow uploads `artifacts/predeployment` containing:

- committed frontend lockfile copy and `committed-lockfile` status
- frontend Node/npm versions, AJV resolution, and build file list
- backend image inspect and layer history
- image healthcheck metadata
- runtime UID and Terraform version
- backend health response and container log
- kubectl client version
- rendered Kubernetes packages and document-count summary
- verification summary including `frontend_lockfile=committed`

These files are validation evidence, not proof that an AWS deployment occurred.
