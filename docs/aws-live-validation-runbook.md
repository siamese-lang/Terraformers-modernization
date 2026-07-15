# AWS Live Validation Runbook

This runbook defines the first controlled AWS/EKS live validation path for Terraformers modernization.

It does not add automation. It connects the Terraform, Kubernetes manifest, deployment package, smoke, and evidence paths that already exist in the repository into one operator-run sequence.

## Scope

```text
Goal:
- Provision the minimum AWS runtime stack needed for a private backend smoke.
- Keep all apply operations operator-controlled and outside CI.
- Prove backend startup, RDS/Cognito/runtime-secret wiring, IRSA annotation, and the upload/project-tree/main.tf API smoke path.

Out of scope:
- No Terraform apply workflow.
- No kubectl apply workflow.
- No ALB ingress or public backend exposure.
- No External Secrets installation.
- No Bedrock/S3/SQS/OpenSearch adapter enablement.
- No Terraform execution UI/API.
```

## Source review

```text
AWS-Terraformers/Terraformers:
- Preserve the original product flow: architecture image upload -> analysis -> Terraform draft -> project save/query -> project tree/main.tf preview -> public project/comment.
- Do not turn the service into a Terraform execution platform.

AWS-Terraformers/Infra-code:
- Reuse the network/EKS concepts already reflected in aws-runtime-network and eks-runtime: VPC, public/private subnets, Kubernetes subnet tags, IGW/NAT concept, S3 gateway endpoint, optional Bedrock Runtime endpoint, EKS OIDC, and managed node group.
- Do not reuse long-lived AWS keys, local-exec kubeconfig mutation, hardcoded region/service values, broad DynamoDB/S3 IAM, or auto-approve apply.

siamese-lang/rdb-refactor:
- Reuse the RDS/Flyway/datasource contract reflected in backend-stateful-dependencies.
- Treat Flyway as the canonical schema path and manual SQL as emergency fallback only.
```

## Reuse / modify / add / exclude

```text
Reuse:
- aws-runtime-network Terraform env
- backend-runtime-dependencies Terraform env
- backend-stateful-dependencies Terraform env
- eks-runtime Terraform env
- backend image publish workflow/output path
- build-aws-runtime-input-bundle.py
- build-aws-runtime-deployment-package.sh
- render-backend-runtime-secret.sh
- render-aws-runtime-manifest.sh
- aws-runtime-deploy-preflight.sh
- aws-runtime-rollout-smoke.sh
- collect-aws-runtime-evidence.sh

Modify:
- This runbook only defines the sequence and operator handoff points.

Add:
- One live validation runbook.

Exclude:
- No new workflow.
- No new script.
- No generated manifest committed.
- No private tfvars committed.
- No secret value committed.
- No public exposure.
- No adapter enablement.
```

## Operator prerequisites

Before starting, the operator must have:

```text
- AWS credentials for the target account, preferably via SSO or an assumed role.
- AWS region selected, default recommendation: ap-northeast-2.
- Terraform CLI compatible with repository validation.
- kubectl.
- AWS CLI.
- jq.
- A built and published backend image URI.
- A secure place for tfvars and output JSON files outside git, for example /tmp/terraformers-live-validation.
```

The operator should also decide the validation ID used in names and evidence:

```bash
export TFV_WORKDIR=/tmp/terraformers-live-validation
export AWS_REGION=ap-northeast-2
export PROJECT_NAME=terraformers-modernization
export ENVIRONMENT=live-smoke
export BACKEND_IMAGE_URI='<account-id>.dkr.ecr.ap-northeast-2.amazonaws.com/<repo>:<tag>'
mkdir -p "$TFV_WORKDIR"
```

## Phase 0: Static verification gate

Run the existing repository gate before provisioning anything.

```bash
bash scripts/checks/terraform-static-verification.sh
```

Stop if this fails.

## Phase 1: Network plan/apply

The network env is the first dependency because it produces `vpc_id`, `private_subnet_ids`, and `private_subnet_cidr_blocks`.

Create a private tfvars file outside git:

```bash
cat > "$TFV_WORKDIR/aws-runtime-network.tfvars" <<EOF
project_name = "$PROJECT_NAME"
environment  = "$ENVIRONMENT"
aws_region   = "$AWS_REGION"
eks_cluster_name = "$PROJECT_NAME-$ENVIRONMENT-backend"

vpc_cidr             = "10.40.0.0/16"
public_subnet_count  = 2
private_subnet_count = 2
subnet_newbits       = 4

enable_nat_gateway              = false
single_nat_gateway              = true
enable_s3_gateway_endpoint      = true
enable_bedrock_runtime_endpoint = false
EOF
```

Run plan, review it, then apply manually only after approval:

```bash
terraform -chdir=infra/terraform/envs/aws-runtime-network init
terraform -chdir=infra/terraform/envs/aws-runtime-network plan \
  -var-file="$TFV_WORKDIR/aws-runtime-network.tfvars" \
  -out="$TFV_WORKDIR/aws-runtime-network.tfplan"

terraform -chdir=infra/terraform/envs/aws-runtime-network apply \
  "$TFV_WORKDIR/aws-runtime-network.tfplan"

terraform -chdir=infra/terraform/envs/aws-runtime-network output -json \
  > "$TFV_WORKDIR/aws-runtime-network-output.json"
```

Stop if the plan includes resources outside the expected VPC/subnet/route-table/endpoint boundary.

## Phase 2: Backend runtime dependencies plan/apply

This env creates the backend image repository/runtime buckets/queues/runtime secret container.

```bash
terraform -chdir=infra/terraform/envs/backend-runtime-dependencies init
terraform -chdir=infra/terraform/envs/backend-runtime-dependencies plan \
  -out="$TFV_WORKDIR/backend-runtime-dependencies.tfplan"

terraform -chdir=infra/terraform/envs/backend-runtime-dependencies apply \
  "$TFV_WORKDIR/backend-runtime-dependencies.tfplan"

terraform -chdir=infra/terraform/envs/backend-runtime-dependencies output -json \
  > "$TFV_WORKDIR/backend-runtime-dependencies-output.json"
```

Stop if bucket, queue, ECR, or Secrets Manager names conflict with existing resources.

## Phase 3: Backend stateful dependencies plan/apply

This env consumes the network outputs and creates RDS MariaDB and Cognito.

```bash
export VPC_ID="$(jq -r '.vpc_id.value' "$TFV_WORKDIR/aws-runtime-network-output.json")"
export PRIVATE_SUBNET_IDS="$(jq -c '.private_subnet_ids.value' "$TFV_WORKDIR/aws-runtime-network-output.json")"
export PRIVATE_SUBNET_CIDRS="$(jq -c '.private_subnet_cidr_blocks.value' "$TFV_WORKDIR/aws-runtime-network-output.json")"

cat > "$TFV_WORKDIR/backend-stateful-dependencies.tfvars" <<EOF
project_name = "$PROJECT_NAME"
environment  = "$ENVIRONMENT"
aws_region   = "$AWS_REGION"

vpc_id                       = "$VPC_ID"
private_subnet_ids           = $PRIVATE_SUBNET_IDS
allowed_database_cidr_blocks = $PRIVATE_SUBNET_CIDRS

database_manage_master_user_password = true
database_name     = "terraformers"
database_username = "terraformers_app"

database_instance_class       = "db.t4g.micro"
database_allocated_storage_gb = 20
database_multi_az             = false
database_deletion_protection  = false
database_skip_final_snapshot  = true
cognito_deletion_protection   = false
EOF
```

Then run:

```bash
terraform -chdir=infra/terraform/envs/backend-stateful-dependencies init
terraform -chdir=infra/terraform/envs/backend-stateful-dependencies plan \
  -var-file="$TFV_WORKDIR/backend-stateful-dependencies.tfvars" \
  -out="$TFV_WORKDIR/backend-stateful-dependencies.tfplan"

terraform -chdir=infra/terraform/envs/backend-stateful-dependencies apply \
  "$TFV_WORKDIR/backend-stateful-dependencies.tfplan"

terraform -chdir=infra/terraform/envs/backend-stateful-dependencies output -json \
  > "$TFV_WORKDIR/backend-stateful-dependencies-output.json"
```

Stop if the DB is public, deletion policy is not intentional, or the output does not include the datasource URL and master user secret ARN.

## Phase 4: EKS runtime plan/apply

This env consumes network and backend runtime outputs, then creates EKS, node group, OIDC provider, and backend IRSA role.

```bash
export UPLOAD_BUCKET_ARN="$(jq -r '.upload_bucket_arn.value // empty' "$TFV_WORKDIR/backend-runtime-dependencies-output.json")"
export RESULT_BUCKET_ARN="$(jq -r '.result_bucket_arn.value // empty' "$TFV_WORKDIR/backend-runtime-dependencies-output.json")"
export AI_LOG_QUEUE_ARN="$(jq -r '.ai_log_queue_arn.value // empty' "$TFV_WORKDIR/backend-runtime-dependencies-output.json")"
export TERRAFORM_LOG_QUEUE_ARN="$(jq -r '.terraform_log_queue_arn.value // empty' "$TFV_WORKDIR/backend-runtime-dependencies-output.json")"
export BACKEND_RUNTIME_SECRET_ARN="$(jq -r '.backend_runtime_secret_arn.value' "$TFV_WORKDIR/backend-runtime-dependencies-output.json")"

cat > "$TFV_WORKDIR/eks-runtime.tfvars" <<EOF
project_name = "$PROJECT_NAME"
environment  = "$ENVIRONMENT"
aws_region   = "$AWS_REGION"

vpc_id             = "$VPC_ID"
private_subnet_ids = $PRIVATE_SUBNET_IDS

cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["<operator-public-ip>/32"]

node_instance_types = ["t3.medium"]
node_desired_size   = 1
node_min_size       = 1
node_max_size       = 2
node_disk_size      = 30

backend_namespace            = "terraformers-runtime"
backend_service_account_name = "terraformers-backend"

upload_bucket_arn          = "$UPLOAD_BUCKET_ARN"
result_bucket_arn          = "$RESULT_BUCKET_ARN"
ai_log_queue_arn           = "$AI_LOG_QUEUE_ARN"
terraform_log_queue_arn    = "$TERRAFORM_LOG_QUEUE_ARN"
backend_runtime_secret_arn = "$BACKEND_RUNTIME_SECRET_ARN"
bedrock_model_resource_arns = []
EOF
```

Then run:

```bash
terraform -chdir=infra/terraform/envs/eks-runtime init
terraform -chdir=infra/terraform/envs/eks-runtime plan \
  -var-file="$TFV_WORKDIR/eks-runtime.tfvars" \
  -out="$TFV_WORKDIR/eks-runtime.tfplan"

terraform -chdir=infra/terraform/envs/eks-runtime apply \
  "$TFV_WORKDIR/eks-runtime.tfplan"

terraform -chdir=infra/terraform/envs/eks-runtime output -json \
  > "$TFV_WORKDIR/eks-runtime-output.json"
```

Stop if the public EKS API CIDR is broad, the node group size is higher than intended, or the IRSA policy includes adapter permissions that are not part of the smoke.

## Phase 5: Resolve runtime secret values

The deployment package needs `SPRING_DATASOURCE_PASSWORD`. With RDS-managed password enabled, retrieve it manually from the RDS-managed Secrets Manager secret.

```bash
export DATABASE_SECRET_ARN="$(jq -r '.database_master_user_secret_arn.value' "$TFV_WORKDIR/backend-stateful-dependencies-output.json")"
export SPRING_DATASOURCE_PASSWORD="$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$DATABASE_SECRET_ARN" \
  --query SecretString \
  --output text | jq -r '.password')"
```

Do not echo or commit this value. Do not write it to repository paths.

## Phase 6: Build input bundle and deployment package

Reuse the existing deployment package path.

```bash
python3 scripts/deploy/build-aws-runtime-input-bundle.py \
  --runtime-outputs-json "$TFV_WORKDIR/backend-runtime-dependencies-output.json" \
  --stateful-outputs-json "$TFV_WORKDIR/backend-stateful-dependencies-output.json" \
  --eks-outputs-json "$TFV_WORKDIR/eks-runtime-output.json" \
  --database-password "$SPRING_DATASOURCE_PASSWORD" \
  --image-uri "$BACKEND_IMAGE_URI" \
  --output-dir "$TFV_WORKDIR/input-bundle"

aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$(jq -r '.cluster_name.value' "$TFV_WORKDIR/eks-runtime-output.json")"

export KUBE_CONTEXT="$(kubectl config current-context)"

bash scripts/deploy/build-aws-runtime-deployment-package.sh \
  --input-dir "$TFV_WORKDIR/input-bundle" \
  --output-dir "$TFV_WORKDIR/deployment-package" \
  --cluster-check true \
  --server-dry-run true
```

Review:

```text
$TFV_WORKDIR/deployment-package/preflight-report.txt
$TFV_WORKDIR/deployment-package/backend-runtime-secret.yaml
$TFV_WORKDIR/deployment-package/aws-runtime-manifest.yaml
$TFV_WORKDIR/deployment-package/apply-order.txt
```

Stop if preflight fails, the context is wrong, or the manifest references an unexpected image/namespace/IRSA role.

## Phase 7: Manual Kubernetes apply

Apply only after reviewing the generated package.

```bash
kubectl --context "$KUBE_CONTEXT" create namespace terraformers-runtime || true
kubectl --context "$KUBE_CONTEXT" apply -f "$TFV_WORKDIR/deployment-package/backend-runtime-secret.yaml"
kubectl --context "$KUBE_CONTEXT" apply -f "$TFV_WORKDIR/deployment-package/aws-runtime-manifest.yaml"
```

This remains a manual boundary. Do not convert these commands into a workflow until live validation has produced evidence and the rollout model is reviewed.

## Phase 8: Rollout smoke and evidence collection

Run the existing smoke path:

```bash
bash scripts/deploy/aws-runtime-rollout-smoke.sh \
  --namespace terraformers-runtime \
  --context "$KUBE_CONTEXT" \
  --project-id aws-runtime-smoke
```

Then collect evidence:

```bash
export BACKEND_IRSA_ROLE_ARN="$(jq -r '.backend_irsa_role_arn.value' "$TFV_WORKDIR/eks-runtime-output.json")"

bash scripts/deploy/collect-aws-runtime-evidence.sh \
  --namespace terraformers-runtime \
  --context "$KUBE_CONTEXT" \
  --package-dir "$TFV_WORKDIR/deployment-package" \
  --smoke-dir artifacts/aws-runtime-rollout-smoke \
  --output-dir artifacts/aws-runtime-evidence \
  --image-uri "$BACKEND_IMAGE_URI" \
  --irsa-role-arn "$BACKEND_IRSA_ROLE_ARN" \
  --cluster-check true
```

The first successful live validation should produce:

```text
- Terraform output JSON files outside git.
- deployment-package/preflight-report.txt.
- rollout smoke artifacts.
- aws-runtime-evidence directory.
```

## Success criteria

```text
- Terraform plan/apply sequence completed manually in the expected order.
- No generated tfvars, secret values, kube manifests, or output JSON files were committed.
- EKS backend Deployment became available.
- ServiceAccount uses the expected backend IRSA role annotation.
- Backend health endpoint responds through port-forward smoke.
- Multipart /api/upload smoke succeeds.
- /api/project-tree/{projectId} smoke succeeds.
- /api/projects/{projectId}/terraform/main.tf smoke succeeds.
- Evidence directory is produced without copying the private Secret manifest.
```

## Stop conditions

Stop immediately when any of the following happens:

```text
- Terraform plan includes unexpected public exposure.
- EKS API public CIDR is broader than the operator-approved CIDR.
- NAT, Bedrock endpoint, or adapter permission is enabled unintentionally.
- RDS is publicly accessible.
- Secret values would be printed, committed, or copied into evidence.
- kubectl context does not match the intended live validation cluster.
- Backend fails because of schema mismatch; treat it as Flyway/schema work, not as a network fix.
- Backend fails because of missing optional adapters; keep adapters disabled until private smoke succeeds.
```

## Next work after a successful private live validation

```text
1. Document actual evidence and any failure analysis.
2. Decide whether to add a controlled ALB/public exposure PR.
3. Decide whether to replace manual secret retrieval with External Secrets.
4. Enable S3 writer, SQS, Bedrock, and OpenSearch adapters one at a time.
5. Only after stable manual evidence, consider a GitOps or approval-gated deployment path.
```
