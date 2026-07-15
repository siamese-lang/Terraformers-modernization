# AWS Runtime Kubernetes Overlay Template

## 1. Purpose

This document explains the public-safe AWS runtime Kubernetes overlay template for the modernized Terraformers backend.

The template is intended to bridge the gap between:

```text
local kind smoke path
  -> build/publish backend image
  -> environment-specific Kubernetes deployment
```

It is not a production deployment by itself. Before applying to a real cluster, copy the template into an environment-specific overlay and replace the placeholder registry image, namespace, runtime Secret delivery, and ServiceAccount annotation.

## 2. Overlay path

```text
infra/kubernetes/overlays/aws-runtime-template
```

The overlay reuses the base manifests:

```text
infra/kubernetes/base
  -> backend Deployment
  -> backend Service
  -> backend ServiceAccount
  -> backend runtime ConfigMap
```

## 3. What the template sets

```text
namespace: terraformers-runtime
image: registry.example.com/terraformers-backend:immutable-tag
SPRING_PROFILES_ACTIVE: prod
AWS_REGION: ap-northeast-2
```

It keeps all production adapters disabled by default:

```text
S3_READER_ENABLED=false
S3_WRITER_ENABLED=false
BEDROCK_PROVIDER_ENABLED=false
BEDROCK_EMBEDDING_ENABLED=false
OPENSEARCH_RETRIEVER_ENABLED=false
ANALYSIS_SQS_PUBLISHER_ENABLED=false
```

This means the overlay prepares the service for a production-shaped runtime but does not claim that S3, SQS, Bedrock, OpenSearch, Cognito, or RDS have already been validated in a real AWS environment.

## 4. Runtime Secret boundary

The overlay intentionally keeps the base Deployment's Secret reference:

```text
terraformers-backend-runtime-secrets
```

Do not commit this Secret with real values.

Provide it through an environment-specific mechanism such as:

```text
External Secrets
Sealed Secrets
CI/CD secret injection
manually created Secret for a temporary private test cluster
```

The expected key shape is documented in:

```text
infra/kubernetes/base/backend-secret.example.yaml
infra/terraform/runtime-contract/locals.tf
infra/terraform/runtime-contract/outputs.tf
```

## 5. Image URI boundary

After `Backend Image Publish` pushes an image to ECR, copy the image URI into the environment-specific overlay:

```yaml
images:
  - name: public.ecr.aws/example/terraformers-backend
    newName: <ecr-repository-uri>
    newTag: <immutable-tag>
```

Use immutable tags or digests for deployment evidence. Avoid mutable `latest` when recording portfolio validation evidence.

## 6. IRSA boundary

The public base ServiceAccount does not include an AWS account-specific IAM role ARN.

In a private environment overlay, add the IRSA annotation only after the role is created:

```yaml
metadata:
  annotations:
    eks.amazonaws.com/role-arn: <backend-runtime-role-arn>
```

Do not commit a real account-specific ARN to the public base or template overlay.

## 7. Deployment sequence

Recommended sequence:

```text
1. Run Backend Local Verification.
2. Run Runtime Contract Verification.
3. Run Kind Local Stub Smoke.
4. Run Backend Image Publish in build-only mode.
5. Push image to ECR when registry/IAM are ready.
6. Copy aws-runtime-template to an environment-specific overlay.
7. Replace image URI, namespace, Secret provider, and IRSA annotation.
8. Keep all adapters disabled for the first rollout.
9. Apply overlay to EKS.
10. Verify rollout, health, and core API smoke.
11. Enable one adapter at a time with a separate validation path.
```

## 8. Non-goals

Do not use this template PR to add:

```text
EKS cluster creation
ECR repository creation
RDS/Cognito/S3/SQS/Bedrock/OpenSearch production resources
Terraform apply/destroy APIs
browser AWS credential controls
full production adapter enablement
```

Those must be handled as separate, smaller PRs or private environment configuration steps.

## 9. Portfolio explanation

```text
로컬 kind 검증으로 백엔드 컨테이너가 Kubernetes에서 실제로 기동되는 것을 확인한 뒤, EKS 배포를 위해 별도의 AWS runtime overlay 템플릿을 분리했습니다. 이 템플릿은 base manifest를 재사용하되, image URI, namespace, prod profile, runtime Secret, IRSA, adapter switch를 환경별로 바꿀 수 있는 위치를 명확히 합니다. 실제 AWS 계정값이나 Secret은 공개 저장소에 넣지 않고, production adapter는 한 번에 켜지 않도록 경계를 유지했습니다.
```
