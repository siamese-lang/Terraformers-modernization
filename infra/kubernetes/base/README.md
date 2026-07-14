# Kubernetes Base Manifests

## 1. Purpose

This directory contains a public-safe Kubernetes skeleton for the Terraformers backend modernization baseline.

It is designed to show the runtime contract without committing real secrets, account IDs, queue URLs, bucket names, IAM role ARNs, kubeconfig, or environment-specific overlays.

## 2. Rendered by kustomization

`kustomization.yaml` renders only non-secret base resources:

```text
backend-serviceaccount.yaml
backend-configmap.yaml
backend-deployment.yaml
backend-service.yaml
```

`backend-secret.example.yaml` is intentionally excluded. It documents required Secret keys only and must not be applied as-is.

## 3. Runtime Secret creation

Create `terraformers-backend-runtime-secrets` through one of the following environment-specific mechanisms:

- External Secrets connected to AWS Secrets Manager;
- Sealed Secrets;
- private Kustomize overlay;
- CI/CD secret injection.

The required key shape is documented in `backend-secret.example.yaml`.

## 4. IRSA annotation

`backend-serviceaccount.yaml` does not include a real IAM role ARN.

Add the annotation in an environment-specific overlay:

```yaml
metadata:
  annotations:
    eks.amazonaws.com/role-arn: <backend-runtime-role-arn>
```

Do not commit a real account-specific role ARN to the public base manifest.

## 5. Validation

Render the base skeleton:

```bash
kubectl kustomize infra/kubernetes/base
```

Before applying to a cluster, ensure the runtime Secret exists or is created by the same environment overlay.
