# AWS Runtime Deploy Preflight and Smoke

This document defines the boundary between rendered Kubernetes manifests and a real EKS rollout.

The repository now provides these deployment inputs:

```text
backend image URI
  -> produced by Backend Image Publish

backend runtime Secret manifest
  -> produced by scripts/deploy/render-backend-runtime-secret.sh

AWS runtime Kubernetes manifest
  -> produced by scripts/deploy/render-aws-runtime-manifest.sh

EKS cluster and backend IRSA role
  -> produced by infra/terraform/envs/eks-runtime
```

This page covers the last safety checks before applying those manifests and the smoke checks after the backend is deployed.

## Reuse / modify / exclude

```text
Reuse:
Existing rendered AWS runtime manifest
Existing rendered backend runtime Secret manifest
Existing Kubernetes ServiceAccount, SecretRef, Deployment, and Service contracts

Modify:
Add preflight and smoke command paths

Exclude:
No automatic production apply in CI
No generated manifest committed
No public traffic exposure
No ALB ingress
No adapter enablement
No backend API behavior change
```

## 1. Render the Secret manifest

Create a private env file outside the repository or in an ignored local path.

```bash
cp infra/kubernetes/runtime-secret.env.example /tmp/terraformers-runtime-secret.env
# edit /tmp/terraformers-runtime-secret.env with real Terraform outputs and private values
```

Render the Secret manifest.

```bash
bash scripts/deploy/render-backend-runtime-secret.sh \
  --env-file /tmp/terraformers-runtime-secret.env \
  --namespace terraformers-runtime \
  --output /tmp/terraformers-backend-runtime-secret.yaml
```

The script validates required keys and rejects angle-bracket placeholder values. It does not apply the Secret.

## 2. Render the AWS runtime manifest

Use the pushed backend image URI and the backend IRSA role ARN from Terraform output.

```bash
bash scripts/deploy/render-aws-runtime-manifest.sh \
  --image-uri "$BACKEND_IMAGE_URI" \
  --irsa-role-arn "$BACKEND_IRSA_ROLE_ARN" \
  --namespace terraformers-runtime \
  --output /tmp/terraformers-aws-runtime.yaml
```

The script rejects missing image URI, missing IRSA role ARN, angle-bracket placeholders, untagged image values, and `latest` image tags by default.

## 3. Run deploy preflight

For a real EKS cluster, run with cluster checks and server-side dry-run enabled.

```bash
bash scripts/deploy/aws-runtime-deploy-preflight.sh \
  --runtime-manifest /tmp/terraformers-aws-runtime.yaml \
  --secret-manifest /tmp/terraformers-backend-runtime-secret.yaml \
  --namespace terraformers-runtime \
  --context "$KUBE_CONTEXT" \
  --cluster-check true \
  --server-dry-run true
```

The preflight checks:

```text
- manifest files exist
- obvious placeholder values are absent
- runtime manifest contains Deployment, ServiceAccount, Service, prod profile, SecretRef, and IRSA annotation
- Secret manifest creates terraformers-backend-runtime-secrets
- namespace exists
- kubectl auth can-i checks pass for core resources
- client-side dry-run succeeds
- server-side dry-run succeeds
```

For CI or local static validation without a cluster:

```bash
bash scripts/deploy/aws-runtime-deploy-preflight.sh \
  --runtime-manifest /tmp/terraformers-aws-runtime.yaml \
  --secret-manifest /tmp/terraformers-backend-runtime-secret.yaml \
  --namespace terraformers-runtime \
  --cluster-check false \
  --server-dry-run false
```

## 4. Manual apply boundary

Only after preflight passes, apply the Secret and runtime manifest manually.

```bash
kubectl --context "$KUBE_CONTEXT" create namespace terraformers-runtime || true
kubectl --context "$KUBE_CONTEXT" apply -f /tmp/terraformers-backend-runtime-secret.yaml
kubectl --context "$KUBE_CONTEXT" apply -f /tmp/terraformers-aws-runtime.yaml
```

This repository intentionally does not run that apply step in CI.

## 5. Rollout and API smoke

After the manifests are applied, run:

```bash
bash scripts/deploy/aws-runtime-rollout-smoke.sh \
  --namespace terraformers-runtime \
  --context "$KUBE_CONTEXT" \
  --project-id aws-runtime-smoke
```

The smoke script checks:

```text
- Deployment rollout completed
- backend pod is Running
- Service port-forward works
- /actuator/health responds
- multipart POST /api/upload creates a smoke project
- /api/project-tree/{projectId} responds
- /api/projects/{projectId}/terraform/main.tf responds
```

Smoke evidence is written to:

```text
artifacts/aws-runtime-rollout-smoke/
```

## Validation workflow

Run this workflow before merging changes to the deploy scripts:

```text
AWS Runtime Deploy Preflight Verification
```

It renders public-safe sample manifests, runs static preflight with `--cluster-check false`, and verifies that placeholder runtime images are rejected.

## Stop condition

This deploy path is ready when:

```text
- Backend image is published to a registry
- Runtime dependency Terraform outputs are available
- Stateful dependency Terraform outputs are available
- EKS runtime Terraform outputs are available
- Runtime Secret manifest renders from private env values
- AWS runtime manifest renders from image URI and IRSA ARN
- Deploy preflight passes against the target cluster
- Rollout smoke passes after manual apply
```

Do not enable Bedrock, S3 writer, SQS publisher, or OpenSearch adapter in the first EKS smoke. First prove that the backend starts and the core project metadata/tree/main.tf API path works with production-shaped infrastructure.
