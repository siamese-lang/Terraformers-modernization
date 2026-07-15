# AWS Runtime Evidence Collection

This document defines the evidence collection step after a manual AWS runtime rollout.

The repository already provides these pieces:

```text
Terraform outputs
  -> scripts/deploy/build-aws-runtime-input-bundle.py

input bundle
  -> scripts/deploy/build-aws-runtime-deployment-package.sh
  -> backend-runtime-secret.yaml
  -> aws-runtime-manifest.yaml
  -> preflight-report.txt
  -> apply-order.txt

manual apply boundary
  -> reviewed and executed outside CI

rollout smoke
  -> scripts/deploy/aws-runtime-rollout-smoke.sh
  -> artifacts/aws-runtime-rollout-smoke
```

`collect-aws-runtime-evidence.sh` does not deploy anything. It gathers the package, Kubernetes, and smoke evidence into one reviewable directory.

## Reuse / modify / exclude

```text
Reuse:
Existing AWS runtime deployment package
Existing deploy preflight report
Existing manual apply boundary
Existing rollout smoke script and smoke outputs
Existing Kubernetes Deployment, ServiceAccount, Service, and SecretRef contracts

Modify:
Add one evidence collection command and verification workflow

Exclude:
No terraform apply
No kubectl apply
No public traffic exposure
No ALB ingress
No External Secrets installation
No Bedrock/S3/SQS/OpenSearch adapter enablement
No backend API behavior change
```

## 1. Generate the deployment package

Before deployment, build the package from the AWS runtime input bundle.

```bash
bash scripts/deploy/build-aws-runtime-deployment-package.sh \
  --input-dir /tmp/terraformers-input-bundle \
  --output-dir /tmp/terraformers-deployment-package \
  --cluster-check true \
  --server-dry-run true
```

Review `preflight-report.txt`, `backend-runtime-secret.yaml`, and `aws-runtime-manifest.yaml` before applying anything.

## 2. Apply manually

This repository intentionally keeps `kubectl apply` outside CI and outside the evidence collection script. Use the package's generated `apply-order.txt` only after reviewing the target context and manifests.

```bash
kubectl --context "$KUBE_CONTEXT" create namespace terraformers-runtime || true
kubectl --context "$KUBE_CONTEXT" apply -f /tmp/terraformers-deployment-package/backend-runtime-secret.yaml
kubectl --context "$KUBE_CONTEXT" apply -f /tmp/terraformers-deployment-package/aws-runtime-manifest.yaml
```

## 3. Run rollout smoke

After the manual apply, run the existing smoke path.

```bash
bash scripts/deploy/aws-runtime-rollout-smoke.sh \
  --namespace terraformers-runtime \
  --context "$KUBE_CONTEXT" \
  --project-id aws-runtime-smoke
```

The smoke script writes:

```text
artifacts/aws-runtime-rollout-smoke/
  rollout-status.txt
  pods.txt
  endpoints.yaml
  port-forward.log
  health.json
  upload-response.json
  project-tree.json
  main-tf-response.json
```

## 4. Collect evidence

Run evidence collection after the smoke script.

```bash
bash scripts/deploy/collect-aws-runtime-evidence.sh \
  --namespace terraformers-runtime \
  --context "$KUBE_CONTEXT" \
  --package-dir /tmp/terraformers-deployment-package \
  --smoke-dir artifacts/aws-runtime-rollout-smoke \
  --output-dir artifacts/aws-runtime-evidence \
  --image-uri "$BACKEND_IMAGE_URI" \
  --irsa-role-arn "$BACKEND_IRSA_ROLE_ARN" \
  --cluster-check true
```

The evidence directory contains:

```text
artifacts/aws-runtime-evidence/
  metadata.txt
  evidence-checklist.txt
  deployment-package/
    manifest-sha256.txt
    preflight-report.txt
    apply-order.txt
    README.txt
  kubernetes/
    context.txt
    namespace.yaml
    deployment.yaml
    deployment-describe.txt
    replicasets.txt
    pods-wide.txt
    pods.yaml
    service.yaml
    serviceaccount.yaml
    endpoints.yaml
    events.txt
    backend-logs.txt
  smoke/
    rollout-status.txt
    pods.txt
    endpoints.yaml
    port-forward.log
    health.json
    upload-response.json
    project-tree.json
    main-tf-response.json
```

The script records hashes for `backend-runtime-secret.yaml` and `aws-runtime-manifest.yaml` instead of copying the Secret manifest into the evidence directory. This preserves traceability without duplicating private runtime values into another artifact path.

## Static verification mode

For CI or local dry verification without a cluster:

```bash
bash scripts/deploy/collect-aws-runtime-evidence.sh \
  --cluster-check false \
  --package-dir /tmp/terraformers-deployment-package \
  --smoke-dir artifacts/aws-runtime-rollout-smoke \
  --output-dir artifacts/aws-runtime-evidence
```

In this mode, the script still builds metadata, checklist, package hashes, and smoke copies, but it does not call `kubectl`.

## Validation workflow

Run:

```text
AWS Runtime Evidence Collection Verification
```

The workflow creates public-safe deployment package and smoke fixtures, runs collection in static mode, verifies generated evidence files, and confirms that the Secret manifest is not copied into the evidence artifact.

## Stop condition

This step is complete when:

```text
- deployment package evidence is referenced by hash and preflight report
- rollout smoke evidence is copied into a single reviewable directory
- Kubernetes evidence collection path is defined for a live cluster
- static verification passes without requiring a cluster
- no apply, public ingress, or adapter enablement is introduced
```

The next live rollout should still keep optional adapters disabled. Prove backend startup and the upload/project-tree/main.tf path first, then handle S3, SQS, Bedrock, and OpenSearch as separate adapter enablement PRs.
