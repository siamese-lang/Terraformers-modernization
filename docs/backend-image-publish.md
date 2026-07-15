# Backend Image Publish Path

## 1. Purpose

This document defines the image build and optional publish path for the modernized Terraformers backend.

The goal is to produce an immutable backend image URI that can be referenced by an environment-specific Kubernetes overlay.

This path does not create AWS infrastructure. It assumes the target container registry, repository, IAM permissions, and credentials already exist.

## 2. Existing build-only baseline

The repository already includes a build-only workflow:

```text
Backend Image Build Verification
```

That workflow verifies that `backend/Dockerfile` can build a backend container image. It does not push the image to any registry.

## 3. Optional publish workflow

This PR adds:

```text
Backend Image Publish
```

The workflow accepts:

```text
image_uri
push_image
aws_region
aws_role_to_assume
```

Recommended ECR image URI shape:

```text
<account-id>.dkr.ecr.<region>.amazonaws.com/terraformers-backend:<git-sha-or-release-tag>
```

Do not use mutable tags such as `latest` as the deployment reference.

## 4. Build-only verification mode

Use this first when checking the workflow without AWS credentials:

```text
push_image=false
image_uri=terraformers-backend:manual
```

Behavior:

```text
1. builds backend/Dockerfile
2. inspects the image
3. uploads backend-image-publish-evidence artifact
4. does not configure AWS credentials
5. does not push to a registry
```

## 5. ECR publish mode

Use this only when an ECR repository and IAM path are ready:

```text
push_image=true
image_uri=<account-id>.dkr.ecr.<region>.amazonaws.com/terraformers-backend:<immutable-tag>
aws_region=<region>
aws_role_to_assume=<optional-github-oidc-role-arn>
```

If `aws_role_to_assume` is empty, the workflow expects repository secrets:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN optional
```

Behavior:

```text
1. builds backend/Dockerfile
2. validates that image_uri looks like an ECR registry URI
3. logs in to ECR
4. pushes the image
5. uploads backend-image-publish-evidence artifact
```

## 6. Kubernetes deployment connection

After a real image is pushed, do not edit `infra/kubernetes/base` directly.

Create or update an environment-specific overlay that sets the backend image to the immutable image URI.

Example target state:

```text
images:
  - name: public.ecr.aws/example/terraformers-backend
    newName: <account-id>.dkr.ecr.<region>.amazonaws.com/terraformers-backend
    newTag: <immutable-tag>
```

The existing `local-stub` overlay intentionally uses:

```text
terraformers-backend:local-stub
imagePullPolicy=Never
```

That is only for local kind smoke testing and should not be used for EKS.

## 7. Production boundary

Publishing a backend image is not the same as production deployment.

Before EKS rollout, the environment overlay must also define or inject:

```text
runtime Secret source
ServiceAccount IRSA annotation
real image registry URI and immutable tag
SPRING_PROFILES_ACTIVE=prod
adapter switches
RDS/Cognito/S3/SQS/Bedrock/OpenSearch runtime values as applicable
```

Enable production adapters one at a time and validate each with its own workflow or runbook.
