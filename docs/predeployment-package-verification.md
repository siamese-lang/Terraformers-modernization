# Pre-deployment Package Verification

## Purpose

This gate proves that the modernized service can be built, packaged, and statically reconciled without publishing an image or changing an AWS account or Kubernetes cluster.

It verifies four delivery contracts:

1. the React production bundle
2. the Spring Boot backend runtime image
3. the Kubernetes base, local-stub, and AWS runtime-template packages
4. the private AWS runtime input bundle generated from Terraform output JSON

## Safety boundary

The workflow does not perform any of the following:

- Docker image push
- AWS authentication or resource creation
- Terraform plan/apply/destroy
- Kubernetes apply against a cluster
- External Secrets installation
- Bedrock, OpenSearch, SQS, or S3 production-adapter enablement

Kubernetes resources are rendered and structurally checked without contacting a Kubernetes API server.

## Frontend dependency gate

`frontend/package-lock.json` is a required delivery input. CI does not generate or repair it.

The package job runs:

```text
committed lockfile check
AJV root compatibility checks
npm ci
AJV runtime module-resolution checks
npm run build
```

The root build dependency is pinned to `ajv@8.20.0` with `ajv-keywords@5.1.0`, while older AJV 6 copies remain nested for legacy CRA loaders. Node/npm versions, lock resolution, runtime module path, dependency tree, and build files are recorded as evidence.

## Backend image verification

The workflow builds `backend/Dockerfile` with local verification tags. The image must declare non-root UID `10001`, contain the application JAR and pinned Terraform CLI, expose a healthcheck, start with local adapters, and return a successful Actuator health response.

No image is pushed.

## Kubernetes package verification

The workflow renders:

```text
infra/kubernetes/base
infra/kubernetes/overlays/local-stub
infra/kubernetes/overlays/aws-runtime-template
```

The offline gate uses `kubectl kustomize`, not API-discovery-based validation. Each package must contain complete ConfigMap, ServiceAccount, Service, and Deployment documents, contain no committed Secret resource, enforce non-root execution, block privilege escalation, and include the startup probe.

The local overlay must reference the locally built image with `imagePullPolicy: Never`. The AWS template must retain an explicit immutable image replacement contract and never use `latest`.

## AWS runtime input bundle verification

Fixture `terraform output -json` documents exercise the same input builder used by the private deployment package path.

The gate proves that:

- `BACKEND_IMAGE_URI` belongs to Terraform output `backend_image_repository_url`
- an image from a different repository is rejected
- namespace, ServiceAccount, IRSA role, and Kubernetes Secret identities come from the expected Terraform outputs
- the base runtime Secret contains the eight production keys plus `ANALYSIS_RESULT_BUCKET_NAME`
- Bedrock, embedding, OpenSearch, and SQS settings are absent while their adapters remain disabled
- the source map contains the managed-secret pointers but never the database password
- Secret rendering is client-side only and writes to a private output file rather than standard output

The bundle records `runtime_secret_provider=unresolved` because the final managed-secret synchronization mechanism has not yet been selected or verified.

## Evidence

The combined workflow uploads:

- `aws-environment-contract-evidence`
  - repository-wide Terraform and GitHub reference inventory
  - corrected nested `vars.*` and `secrets.*` references
  - fixture runtime input bundle and Secret render evidence
- `predeployment-package-evidence`
  - committed lockfile status and frontend dependency/build evidence
  - backend image metadata, health, runtime UID, Terraform version, and logs
  - rendered Kubernetes packages and document-count summary

These artifacts are validation evidence, not proof that an AWS deployment occurred. The root `artifacts/` directory is ignored locally because it may contain generated private deployment inputs or downloaded CI evidence.
