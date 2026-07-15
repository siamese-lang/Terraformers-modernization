# Kubernetes Runtime Secret Bootstrap

## 1. Purpose

The production-shaped Kubernetes base deployment loads runtime values from this Secret:

```text
terraformers-backend-runtime-secrets
```

The Deployment references that Secret through `envFrom.secretRef`, so the backend Pod will not become ready in the AWS runtime overlay unless the Secret exists in the target namespace.

This document defines the smallest safe bootstrap path for creating that Secret without committing secret values or generated Secret manifests.

## 2. Files

```text
infra/kubernetes/runtime-secret.env.example
  -> public-safe example shape for required runtime keys

scripts/deploy/render-backend-runtime-secret.sh
  -> validates a private env file
  -> renders a Kubernetes Secret manifest through kubectl client-side dry-run
  -> does not apply the Secret to a cluster

scripts/checks/kubernetes-runtime-secret-verification.sh
  -> verifies the example env shape
  -> verifies rendered Secret metadata
  -> verifies required-key rejection

.github/workflows/kubernetes-runtime-secret-verification.yml
  -> manual GitHub Actions validation for the render path
```

## 3. Create a private runtime env file

Copy the public-safe example outside the repository or into an ignored local path:

```bash
cp infra/kubernetes/runtime-secret.env.example /tmp/terraformers-backend-runtime.env
```

Fill it with values from these Terraform outputs and operator-provided secrets:

```text
backend-runtime-dependencies:
  upload bucket name
  result bucket name
  AI log queue URL
  Terraform log queue URL

backend-stateful-dependencies:
  datasource URL
  database username
  database password input
  Cognito region
  Cognito user pool ID
  Cognito app client ID
  Cognito JWKS URL

operator supplied or separately validated:
  Bedrock model ID
  Bedrock embedding model ID
  OpenSearch endpoint
  index name
  vector field name
  content field name
```

Do not commit the filled env file.

## 4. Render the Secret manifest

```bash
scripts/deploy/render-backend-runtime-secret.sh \
  --env-file /tmp/terraformers-backend-runtime.env \
  --namespace terraformers-runtime \
  --output /tmp/terraformers-backend-runtime-secret.yaml
```

Review the generated manifest locally. It should contain:

```text
kind: Secret
metadata.name: terraformers-backend-runtime-secrets
metadata.namespace: terraformers-runtime
type: Opaque
```

## 5. Apply manually during an environment rollout

After review, apply it explicitly:

```bash
kubectl apply -f /tmp/terraformers-backend-runtime-secret.yaml
```

This apply step is intentionally not automated in this PR because secret creation depends on environment-specific values and operator review.

## 6. Verify the bootstrap path

Run locally:

```bash
bash scripts/checks/kubernetes-runtime-secret-verification.sh
```

Or run the manual GitHub Actions workflow:

```text
Kubernetes Runtime Secret Verification
```

## 7. Deployment order

Use this order for an AWS-backed runtime smoke:

```text
1. apply backend-runtime-dependencies Terraform
2. apply backend-stateful-dependencies Terraform
3. apply eks-runtime Terraform
4. publish backend image
5. prepare private runtime env file
6. render and apply terraformers-backend-runtime-secrets
7. copy aws-runtime-template into an environment overlay
8. replace image URI and service account annotation
9. apply the environment overlay
10. check rollout, actuator health, and API smoke path
```

## 8. Excluded scope

This bootstrap path does not:

```text
install External Secrets
create Secret values in Secrets Manager
sync Secrets Manager into Kubernetes
apply Kubernetes manifests automatically
expose the backend publicly
turn on production adapters
change backend API behavior
```

External Secrets or Sealed Secrets can be added later, but that should be a separate PR after the direct Secret bootstrap path is proven.
