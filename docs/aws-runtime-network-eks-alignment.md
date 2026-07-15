# AWS Runtime Network and EKS Alignment

This document records the source-reuse-first alignment for the AWS runtime network and EKS Terraform paths.

## Source review

```text
AWS-Terraformers/Terraformers:
- The product identity remains architecture image upload, component analysis, Terraform draft generation, project save/query, project-tree/main.tf preview, and public project/comment flows.
- This PR does not change backend or frontend product behavior.

AWS-Terraformers/Infra-code:
- `modules/network` already contains the reusable network concepts: VPC, public/private subnets, Kubernetes subnet discovery tags, Internet Gateway, NAT Gateway, S3 gateway endpoint, and Bedrock Runtime VPC endpoint.
- `modules/eks` already contains the reusable EKS concepts: cluster role, EKS VPC resource controller policy, private subnet cluster placement, control-plane logs, OIDC provider, managed node group, node disk sizing, and node labels.
- The original implementation also contains elements that should not be copied as-is: hardcoded `us-west-2` service names, always-on NAT, broad S3/DynamoDB policy attachments, and local-exec kubeconfig mutation.

siamese-lang/rdb-refactor:
- The deployment reuse inventory identifies Terraform quality gates, output extraction, EKS kubeconfig sequencing, and GitOps structure as reusable concepts.
- It also flags long-lived AWS keys, `terraform apply -auto-approve`, DynamoDB-era outputs, hardcoded runtime values, and cross-repository mutation as must-change items.
```

## Reuse / modify / add / exclude

```text
Reuse:
- Original Infra-code public/private subnet split.
- Original Infra-code Kubernetes subnet discovery tags.
- Original Infra-code IGW/NAT/S3 endpoint/Bedrock endpoint concepts.
- Original Infra-code EKS cluster, OIDC provider, node group, node disk sizing, and node label concepts.
- Existing modernization `eks-runtime` env and least-privilege backend IRSA policy shape.

Modify:
- Replace original `test_vpc`/`test_subnet` naming with `aws-runtime-network` names and tags.
- Replace hardcoded service region names with `var.aws_region`.
- Make NAT optional and default it to false for cost-controlled validation.
- Make Bedrock Runtime interface endpoint optional and default it to false so this PR does not enable the Bedrock adapter.
- Keep `eks-runtime` as the EKS/IRSA owner, but add the EKS VPC resource controller policy and node disk/label variables.
- Add runtime network outputs that directly feed `backend-stateful-dependencies` and `eks-runtime` inputs.

Add:
- `infra/terraform/envs/aws-runtime-network`.
- `terraform.tfvars.example` for the runtime network.
- `cluster_security_group_id` and `node_role_arn` outputs from `eks-runtime`.
- Static verification coverage for the new network env.

Exclude:
- No Terraform apply automation.
- No kubectl apply automation.
- No ALB ingress or public backend exposure.
- No External Secrets installation.
- No Bedrock/S3/SQS/OpenSearch adapter enablement.
- No DynamoDB-era output restoration.
- No long-lived AWS credentials.
- No local-exec kubeconfig mutation.
- No Terraform execution UI/API.
```

## Runtime wiring

The intended live-validation flow after this alignment is:

```text
aws-runtime-network outputs:
- vpc_id
- private_subnet_ids
- private_subnet_cidr_blocks

backend-stateful-dependencies inputs:
- vpc_id
- private_subnet_ids
- allowed_database_cidr_blocks or later security-group boundary

eks-runtime inputs:
- vpc_id
- private_subnet_ids
- backend-runtime-dependencies ARNs
```

This PR only makes the Terraform boundaries explicit. It does not run Terraform, update kubeconfig, apply Kubernetes manifests, or expose the backend publicly.

## Validation boundary

`Terraform Static Verification` must pass before merge. That check now includes:

```text
infra/terraform/envs/aws-runtime-network
```

## Stop condition

This alignment is complete when:

```text
- Terraform Static Verification passes.
- aws-runtime-network validates with optional NAT and optional Bedrock endpoint disabled by default.
- eks-runtime keeps existing private subnet cluster placement and IRSA behavior.
- network outputs can feed backend-stateful-dependencies and eks-runtime.
- no apply automation, public exposure, External Secrets installation, adapter enablement, or Terraform execution UI/API is introduced.
```
