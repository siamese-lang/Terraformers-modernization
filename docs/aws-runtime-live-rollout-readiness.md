# AWS Runtime Live Rollout Readiness

This document defines the final operator readiness gate before manually applying the AWS runtime deployment package to EKS.

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
  -> reviewed and executed by the operator, not by CI

rollout smoke
  -> scripts/deploy/aws-runtime-rollout-smoke.sh
  -> artifacts/aws-runtime-rollout-smoke

evidence collection
  -> scripts/deploy/collect-aws-runtime-evidence.sh
  -> artifacts/aws-runtime-evidence
```

`check-aws-runtime-live-rollout-readiness.sh` sits between the deployment package and the manual apply step. It verifies that the package is internally consistent, that the preflight completed, that the first rollout does not expose public traffic, and that the next required steps are explicit.

## Reuse / modify / exclude

```text
Reuse:
Existing AWS runtime deployment package
Existing preflight report
Existing manual apply order
Existing rollout smoke path
Existing evidence collection path
Existing Kubernetes Deployment, ServiceAccount, Service, and SecretRef contracts

Modify:
Add one readiness gate before the operator runs the existing manual apply order

Exclude:
No terraform apply
No terraform destroy
No kubectl apply
No public traffic exposure
No ALB ingress
No External Secrets installation
No Bedrock/S3/SQS/OpenSearch adapter enablement
No backend API behavior change
```

## 1. Build the deployment package

Generate the package from the AWS runtime input bundle.

For a target cluster preflight, use cluster checks and server-side dry-run:

```bash
bash scripts/deploy/build-aws-runtime-deployment-package.sh \
  --input-dir /tmp/terraformers-input-bundle \
  --output-dir /tmp/terraformers-deployment-package \
  --cluster-check true \
  --server-dry-run true
```

The package should contain:

```text
/tmp/terraformers-deployment-package/
  backend-runtime-secret.yaml
  aws-runtime-manifest.yaml
  preflight-report.txt
  apply-order.txt
  README.txt
```

The package builder renders and validates the manifests. It still does not apply them.

## 2. Run the live rollout readiness gate

Run the readiness gate before executing `apply-order.txt`.

```bash
bash scripts/deploy/check-aws-runtime-live-rollout-readiness.sh \
  --package-dir /tmp/terraformers-deployment-package \
  --output-dir artifacts/aws-runtime-live-rollout-readiness \
  --namespace terraformers-runtime \
  --context "$KUBE_CONTEXT" \
  --cluster-check true \
  --expected-image-uri "$BACKEND_IMAGE_URI" \
  --expected-irsa-role-arn "$BACKEND_IRSA_ROLE_ARN"
```

The readiness gate checks:

```text
- required package files exist
- Secret manifest is a terraformers-backend-runtime-secrets Opaque Secret
- runtime manifest contains Deployment, ServiceAccount, Service, prod profile, SecretRef, and IRSA annotation
- runtime manifest does not contain placeholder image values
- runtime manifest does not use a latest image tag
- runtime manifest does not introduce Ingress or LoadBalancer exposure
- preflight-report.txt ends with [aws-runtime-preflight] verification completed
- apply-order.txt contains the manual kubectl apply sequence and rollout smoke command
- apply-order.txt does not contain terraform apply or terraform destroy
- optional cluster context and RBAC checks pass when --cluster-check true
```

The readiness artifact contains:

```text
artifacts/aws-runtime-live-rollout-readiness/
  readiness-report.txt
  rollout-readiness-checklist.txt
  cluster-readiness.txt
  deployment-package/
    package-sha256.txt
    preflight-report.txt
    apply-order.txt
    README.txt
```

The readiness artifact records a hash for `backend-runtime-secret.yaml` but does not copy the Secret manifest into the output directory.

## 3. Manual apply boundary

Only after package generation, preflight, and readiness gate pass should the operator review and execute the package's generated apply order.

```bash
cat /tmp/terraformers-deployment-package/apply-order.txt
```

Then execute the commands manually in the intended shell session and kube context.

This repository intentionally does not run that step in CI. The readiness gate also does not run it.

## 4. Run rollout smoke

After manual apply, run the existing smoke path.

```bash
bash scripts/deploy/aws-runtime-rollout-smoke.sh \
  --namespace terraformers-runtime \
  --context "$KUBE_CONTEXT" \
  --project-id aws-runtime-smoke
```

The smoke path verifies the deployed backend through service port-forward and the product API contract:

```text
- /actuator/health
- multipart POST /api/upload
- GET /api/project-tree/{projectId}
- GET /api/projects/{projectId}/terraform/main.tf
```

## 5. Collect evidence

After the smoke succeeds, collect evidence.

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

This keeps the rollout sequence explicit:

```text
package -> readiness gate -> manual apply -> rollout smoke -> evidence collection
```

## Static verification mode

For CI or local verification without a cluster:

```bash
bash scripts/deploy/check-aws-runtime-live-rollout-readiness.sh \
  --package-dir /tmp/terraformers-deployment-package \
  --output-dir artifacts/aws-runtime-live-rollout-readiness \
  --cluster-check false
```

In this mode, the script still verifies the package structure, preflight report, manual apply order, manifest shape, and no-public-exposure boundary. It does not call `kubectl`.

## Validation workflow

Run:

```text
AWS Runtime Live Rollout Readiness Verification
```

The workflow creates a public-safe deployment package fixture, runs the readiness gate in static mode, verifies the readiness report shape, verifies that the Secret manifest is hashed but not copied, and verifies that `type: LoadBalancer` is rejected.

## Stop condition

This step is complete when:

```text
- the deployment package is accepted by the readiness gate
- readiness-report.txt explicitly says no Terraform or kubectl apply was executed
- package hash evidence is generated
- Secret manifest is not copied into the readiness artifact
- public ingress and LoadBalancer exposure are rejected
- rollout smoke and evidence collection remain the next explicit manual steps
```

The first live rollout should still keep optional adapters disabled. Prove backend startup and the upload/project-tree/main.tf path first, then handle S3 writer, SQS publisher, Bedrock provider, and OpenSearch retriever as separate adapter enablement PRs.
