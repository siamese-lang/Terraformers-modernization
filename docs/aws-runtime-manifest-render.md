# AWS Runtime Manifest Render

## 1. Purpose

This document defines the render step between the AWS runtime Kubernetes overlay template and a real EKS deployment.

The repository now has these deployment boundaries:

```text
backend image publish -> ECR image URI
backend runtime dependencies -> S3/SQS/Secrets Manager outputs
backend stateful dependencies -> RDS/Cognito outputs
EKS runtime -> cluster access and backend IRSA role ARN
runtime Secret bootstrap -> terraformers-backend-runtime-secrets manifest
```

The AWS runtime manifest render step connects the published backend image and the backend IRSA role annotation to the Kubernetes overlay without committing account-specific values.

## 2. Reuse / modify / exclude

```text
Reuse:
infra/kubernetes/overlays/aws-runtime-template
backend runtime Secret name from base Deployment
prod profile and disabled-adapter defaults
backend ServiceAccount name

Modify at render time:
backend image URI
backend ServiceAccount IRSA role annotation
namespace, when needed

Exclude:
No kubectl apply
No generated manifest committed
No Secret values
No External Secrets install
No ALB ingress
No adapter enablement
No backend API behavior change
```

## 3. Required values

Prepare these values from earlier steps:

```text
BACKEND_IMAGE_URI
  -> output or input from Backend Image Publish workflow
  -> example shape: <account>.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend:<immutable-tag>

BACKEND_IRSA_ROLE_ARN
  -> output backend_irsa_role_arn from infra/terraform/envs/eks-runtime

KUBERNETES_NAMESPACE
  -> default: terraformers-runtime
```

The image URI must include an explicit tag. Do not use `latest` unless the script is deliberately run with `ALLOW_LATEST_IMAGE_TAG=true`.

## 4. Render command

From the repository root:

```bash
mkdir -p artifacts/aws-runtime-manifest-render

bash scripts/deploy/render-aws-runtime-manifest.sh \
  --image-uri "$BACKEND_IMAGE_URI" \
  --irsa-role-arn "$BACKEND_IRSA_ROLE_ARN" \
  --namespace terraformers-runtime \
  --output artifacts/aws-runtime-manifest-render/aws-runtime-rendered.yaml
```

The script renders a manifest only. It does not apply anything to the cluster.

## 5. Expected rendered manifest properties

The rendered manifest should contain:

```text
namespace: terraformers-runtime
image: <BACKEND_IMAGE_URI>
eks.amazonaws.com/role-arn: <BACKEND_IRSA_ROLE_ARN>
SPRING_PROFILES_ACTIVE: prod
terraformers-backend-runtime-secrets secretRef
```

The rendered manifest should not contain:

```text
public.ecr.aws/example/terraformers-backend
registry.example.com/terraformers-backend:immutable-tag
replace-with-immutable-tag
angle-bracket placeholders
```

## 6. Validation workflow

Run:

```text
AWS Runtime Manifest Render Verification
```

This workflow uses public-safe sample values to verify that the render script:

```text
1. renders the image URI into the Deployment
2. renders the IRSA role ARN annotation into the ServiceAccount
3. keeps the runtime Secret dependency
4. keeps prod profile and adapters disabled by default
5. rejects missing required inputs
```

## 7. Apply boundary

Apply should happen only after these are ready:

```text
1. EKS cluster exists and kubectl points to the intended cluster
2. backend runtime Secret has been rendered and reviewed
3. backend runtime Secret has been applied to the same namespace
4. backend image exists in ECR
5. rendered manifest has been reviewed
```

Then, in a real environment:

```bash
kubectl apply -f artifacts/aws-runtime-manifest-render/aws-runtime-rendered.yaml
kubectl -n terraformers-runtime rollout status deployment/terraformers-backend
```

Do not expose the service publicly or enable adapters in the same step. First prove that the backend Pod starts and passes health checks with the production-shaped runtime configuration.
