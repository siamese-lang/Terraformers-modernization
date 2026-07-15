# AWS Runtime Input Bundle

This document explains how to turn Terraform outputs and a published backend image URI into the private input files needed by the AWS runtime deployment scripts.

The goal is to remove manual copy/paste drift between these stages:

```text
Terraform outputs
  -> backend-runtime-secret.env
  -> aws-runtime-manifest.env
  -> rendered Kubernetes Secret
  -> rendered AWS runtime manifest
  -> deploy preflight
  -> rollout smoke
```

## Reuse / modify / exclude

```text
Reuse:
Existing Terraform output names
Existing runtime Secret render path
Existing AWS runtime manifest render path
Existing deploy preflight path

Modify:
Add an input bundle builder that maps Terraform outputs into deploy input files

Exclude:
No terraform apply
No kubectl apply
No generated private env files committed
No Secrets Manager secret version creation
No ALB ingress
No adapter enablement
No backend API behavior change
```

## Required inputs

Apply or otherwise prepare these Terraform environments first:

```text
infra/terraform/envs/backend-runtime-dependencies
infra/terraform/envs/backend-stateful-dependencies
infra/terraform/envs/eks-runtime
```

The bundle builder reads these outputs:

```text
backend-runtime-dependencies:
- upload_bucket_name
- result_bucket_name
- ai_log_queue_url
- terraform_log_queue_url

backend-stateful-dependencies:
- spring_datasource_url
- database_username
- cognito_region
- cognito_user_pool_id
- cognito_user_pool_client_id
- cognito_jwks_url

eks-runtime:
- backend_namespace
- backend_irsa_role_arn
```

You must also provide private runtime values that should not be committed:

```text
SPRING_DATASOURCE_PASSWORD
BACKEND_IMAGE_URI
```

The image URI should be an immutable image tag, for example:

```text
123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend:sha-abcdef1
```

`latest` is rejected by default.

## Build the input bundle from live Terraform state

From the repository root:

```bash
python3 scripts/deploy/build-aws-runtime-input-bundle.py \
  --database-password "$SPRING_DATASOURCE_PASSWORD" \
  --image-uri "$BACKEND_IMAGE_URI" \
  --output-dir /tmp/terraformers-aws-runtime-inputs
```

By default, the script runs `terraform output -json` in:

```text
infra/terraform/envs/backend-runtime-dependencies
infra/terraform/envs/backend-stateful-dependencies
infra/terraform/envs/eks-runtime
```

It writes:

```text
/tmp/terraformers-aws-runtime-inputs/backend-runtime-secret.env
/tmp/terraformers-aws-runtime-inputs/aws-runtime-manifest.env
/tmp/terraformers-aws-runtime-inputs/apply-order.txt
```

## Build from saved Terraform output JSON

This is useful when outputs are exported from another terminal or CI job.

```bash
terraform -chdir=infra/terraform/envs/backend-runtime-dependencies output -json > /tmp/backend-runtime-outputs.json
terraform -chdir=infra/terraform/envs/backend-stateful-dependencies output -json > /tmp/backend-stateful-outputs.json
terraform -chdir=infra/terraform/envs/eks-runtime output -json > /tmp/eks-runtime-outputs.json

python3 scripts/deploy/build-aws-runtime-input-bundle.py \
  --runtime-outputs-json /tmp/backend-runtime-outputs.json \
  --stateful-outputs-json /tmp/backend-stateful-outputs.json \
  --eks-outputs-json /tmp/eks-runtime-outputs.json \
  --database-password "$SPRING_DATASOURCE_PASSWORD" \
  --image-uri "$BACKEND_IMAGE_URI" \
  --output-dir /tmp/terraformers-aws-runtime-inputs
```

## Optional adapter values

The first EKS smoke should keep adapters disabled in the Kubernetes runtime config. The Secret still needs the variables because the backend runtime contract expects the keys.

The builder therefore uses disabled-safe defaults for these values unless you override them:

```text
BEDROCK_MODEL_ID=adapter-disabled-bedrock-model
BEDROCK_EMBEDDING_MODEL_ID=adapter-disabled-bedrock-embedding-model
OPENSEARCH_ENDPOINT=https://opensearch-disabled.example.internal
INDEX_NAME=terraformers-reference
VECTOR_FIELD_NAME=embedding
CONTENT_FIELD_NAME=content
```

Override them only when the matching adapter is intentionally enabled and validated.

## Use the generated bundle

Load manifest values:

```bash
set -a
. /tmp/terraformers-aws-runtime-inputs/aws-runtime-manifest.env
set +a
```

Render the Secret manifest:

```bash
bash scripts/deploy/render-backend-runtime-secret.sh \
  --env-file /tmp/terraformers-aws-runtime-inputs/backend-runtime-secret.env \
  --namespace "$KUBERNETES_NAMESPACE" \
  --output /tmp/terraformers-backend-runtime-secret.yaml
```

Render the AWS runtime manifest:

```bash
bash scripts/deploy/render-aws-runtime-manifest.sh \
  --image-uri "$BACKEND_IMAGE_URI" \
  --irsa-role-arn "$BACKEND_IRSA_ROLE_ARN" \
  --namespace "$KUBERNETES_NAMESPACE" \
  --output /tmp/terraformers-aws-runtime.yaml
```

Run preflight:

```bash
bash scripts/deploy/aws-runtime-deploy-preflight.sh \
  --runtime-manifest /tmp/terraformers-aws-runtime.yaml \
  --secret-manifest /tmp/terraformers-backend-runtime-secret.yaml \
  --namespace "$KUBERNETES_NAMESPACE" \
  --context "$KUBE_CONTEXT" \
  --cluster-check true \
  --server-dry-run true
```

Then apply manually only after preflight passes.

## Validation workflow

Run:

```text
AWS Runtime Input Bundle Verification
```

The workflow uses public-safe fixture output JSON and verifies that:

```text
- generated Secret env contains DB, Cognito, S3, SQS, and disabled adapter values
- generated manifest env contains image URI, namespace, and IRSA role ARN
- apply-order.txt points to the render and preflight scripts
- missing database password is rejected
- latest image tag is rejected by default
```

## Stop condition

This stage is complete when the input bundle is generated from real Terraform outputs and can feed the existing Secret render, manifest render, preflight, and rollout smoke scripts without manual value rewriting.
