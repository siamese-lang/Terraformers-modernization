# Terraform EKS Runtime Scaffold

## 1. Purpose

This document describes the EKS runtime Terraform boundary for the modernized Terraformers backend.

The goal is to provide the Kubernetes runtime target that can consume the backend image, runtime Secret, and AWS runtime dependencies that are already separated in earlier Terraform environments.

This is not a one-click production deployment. It is a bounded scaffold for creating the cluster runtime and backend service-account IAM role.

## 2. Scope

```text
Included:
- EKS cluster using existing VPC/private subnet IDs
- managed node group for backend runtime
- EKS OIDC provider
- backend IRSA IAM role
- backend runtime access IAM policy
- outputs needed by Kubernetes overlay/service account annotation

Excluded:
- VPC creation
- NAT gateway / route table creation
- RDS/Cognito creation
- ECR/S3/SQS/Secrets Manager creation
- External Secrets installation
- Kubernetes apply workflow
- ALB Ingress Controller installation
- production traffic exposure
- OpenSearch/AOSS
- Bedrock access validation
```

## 3. Terraform path

```text
infra/terraform/envs/eks-runtime
```

Static validation is included in:

```text
Terraform Static Verification
scripts/checks/terraform-static-verification.sh
```

## 4. Required inputs

The scaffold deliberately consumes existing network and runtime dependency values instead of creating every layer at once.

```text
vpc_id
private_subnet_ids
upload_bucket_arn
result_bucket_arn
ai_log_queue_arn
terraform_log_queue_arn
backend_runtime_secret_arn
```

The bucket, queue, and secret ARNs should come from:

```text
infra/terraform/envs/backend-runtime-dependencies
```

Database and Cognito values come from:

```text
infra/terraform/envs/backend-stateful-dependencies
```

They are not consumed by EKS directly. They should be written into the backend runtime Secret before deploying the backend with the AWS runtime Kubernetes overlay.

## 5. Outputs used by Kubernetes

The key output is:

```text
backend_irsa_role_arn
```

This ARN should be placed on the backend ServiceAccount in an environment-specific Kubernetes overlay:

```yaml
metadata:
  annotations:
    eks.amazonaws.com/role-arn: <backend_irsa_role_arn>
```

The repository does not commit a real role ARN in base or template manifests.

## 6. Apply sequence

Use this order when moving from static verification to an actual AWS runtime:

```text
1. Prepare or select VPC/private subnets.
2. Apply backend-runtime-dependencies.
3. Apply backend-stateful-dependencies.
4. Apply eks-runtime.
5. Publish backend image to ECR.
6. Populate backend runtime Secret values.
7. Copy aws-runtime-template to an environment-specific overlay.
8. Replace image URI and add backend IRSA role annotation.
9. Apply the Kubernetes overlay.
10. Validate rollout, health, and backend API smoke path.
```

Do not enable S3 writer/reader, SQS publisher, Bedrock, and OpenSearch all at once. Enable one adapter at a time and gather evidence for each boundary.

## 7. Public endpoint caution

The example keeps public EKS endpoint access enabled because that is easier to validate from GitHub Actions or an operator workstation.

For a real environment, use one of these safer approaches:

```text
- set cluster_endpoint_public_access=false and operate through a private network path
- keep public access enabled only with a narrow /32 operator CIDR
```

Do not use `0.0.0.0/0` for the cluster API endpoint in a portfolio environment.

## 8. Stop condition

This scaffold is complete when Terraform static validation passes and the outputs clearly connect to the AWS runtime Kubernetes overlay.

Do not add VPC, ALB ingress, External Secrets, or production rollout automation to this PR. Those are separate deployment phases.
