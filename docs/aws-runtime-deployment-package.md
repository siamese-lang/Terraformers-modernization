# AWS Runtime Deployment Package

This document defines the final local artifact packaging step before a manual EKS apply.

The repository already provides these pieces:

```text
Terraform outputs
  -> scripts/deploy/build-aws-runtime-input-bundle.py
  -> backend-runtime-secret.env
  -> aws-runtime-manifest.env

runtime Secret env
  -> scripts/deploy/render-backend-runtime-secret.sh
  -> backend-runtime-secret.yaml

runtime manifest env
  -> scripts/deploy/render-aws-runtime-manifest.sh
  -> aws-runtime-manifest.yaml

rendered manifests
  -> scripts/deploy/aws-runtime-deploy-preflight.sh
  -> preflight result
```

`build-aws-runtime-deployment-package.sh` combines those steps after the input bundle exists.

## Reuse / modify / exclude

```text
Reuse:
Existing AWS runtime input bundle
Existing runtime Secret render path
Existing AWS runtime manifest render path
Existing deploy preflight path
Existing rollout smoke path

Modify:
Add one command that renders a private deployment package from the input bundle

Exclude:
No terraform apply
No kubectl apply
No generated private manifests committed
No public traffic exposure
No ALB ingress
No adapter enablement
No backend API behavior change
```

## 1. Build the input bundle

First generate the input bundle from Terraform outputs and a published backend image URI.

```bash
python3 scripts/deploy/build-aws-runtime-input-bundle.py \
  --database-password "$SPRING_DATASOURCE_PASSWORD" \
  --image-uri "$BACKEND_IMAGE_URI" \
  --output-dir /tmp/terraformers-input-bundle
```

For offline use, pass saved `terraform output -json` files:

```bash
python3 scripts/deploy/build-aws-runtime-input-bundle.py \
  --runtime-outputs-json /tmp/backend-runtime-dependencies-output.json \
  --stateful-outputs-json /tmp/backend-stateful-dependencies-output.json \
  --eks-outputs-json /tmp/eks-runtime-output.json \
  --database-password "$SPRING_DATASOURCE_PASSWORD" \
  --image-uri "$BACKEND_IMAGE_URI" \
  --output-dir /tmp/terraformers-input-bundle
```

## 2. Build the deployment package

For static local validation without connecting to a cluster:

```bash
bash scripts/deploy/build-aws-runtime-deployment-package.sh \
  --input-dir /tmp/terraformers-input-bundle \
  --output-dir /tmp/terraformers-deployment-package \
  --cluster-check false \
  --server-dry-run false
```

For target cluster preflight:

```bash
bash scripts/deploy/build-aws-runtime-deployment-package.sh \
  --input-dir /tmp/terraformers-input-bundle \
  --output-dir /tmp/terraformers-deployment-package \
  --cluster-check true \
  --server-dry-run true
```

The package contains:

```text
backend-runtime-secret.yaml
aws-runtime-manifest.yaml
preflight-report.txt
apply-order.txt
README.txt
```

## 3. Manual apply boundary

The package builder does not apply anything. After reviewing the manifests and preflight result, use the generated `apply-order.txt` as the manual sequence.

Expected order:

```bash
kubectl --context "$KUBE_CONTEXT" create namespace terraformers-runtime || true
kubectl --context "$KUBE_CONTEXT" apply -f /tmp/terraformers-deployment-package/backend-runtime-secret.yaml
kubectl --context "$KUBE_CONTEXT" apply -f /tmp/terraformers-deployment-package/aws-runtime-manifest.yaml
```

Then run rollout smoke:

```bash
bash scripts/deploy/aws-runtime-rollout-smoke.sh \
  --namespace terraformers-runtime \
  --context "$KUBE_CONTEXT" \
  --project-id aws-runtime-smoke
```

## Validation workflow

Run:

```text
AWS Runtime Deployment Package Verification
```

The workflow uses public-safe sample Terraform outputs, creates an input bundle, builds a deployment package, runs static preflight, and verifies the rendered manifest shape.

## Stop condition

This step is complete when:

```text
- input bundle is generated
- Secret manifest is rendered
- AWS runtime manifest is rendered
- static or cluster preflight passes
- apply-order.txt contains the manual apply and smoke sequence
```

The first live rollout should still keep every optional adapter disabled. Prove that the backend starts, connects to required runtime dependencies, and serves the upload/project-tree/main.tf smoke path before enabling S3 writer, Bedrock, SQS, or OpenSearch.
