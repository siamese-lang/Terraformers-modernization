# Terraform AWS Runtime Network

This document defines the AWS network scaffold used to unblock the first live validation of the modernized Terraformers runtime.

The repository already had AWS runtime dependencies, stateful dependencies, and EKS runtime Terraform scaffolds. The missing live-validation prerequisite was a concrete VPC and at least two private subnets that those stacks could share.

## Reuse / modify / exclude

```text
Reuse:
Existing backend-runtime-dependencies Terraform outputs
Existing backend-stateful-dependencies VPC/private-subnet inputs
Existing eks-runtime VPC/private-subnet inputs
Existing Terraform Static Verification workflow

Modify:
Add one AWS runtime network scaffold that can supply VPC and private subnet outputs for live validation

Exclude:
No terraform apply automation
No Kubernetes apply automation
No ALB ingress
No public backend traffic exposure
No External Secrets installation
No Bedrock/S3/SQS/OpenSearch adapter enablement
No backend API behavior change
```

## What this scaffold creates

```text
infra/terraform/envs/aws-runtime-network/
  -> VPC
  -> two or more public subnets
  -> two or more private subnets
  -> Internet Gateway and public route table
  -> optional single NAT gateway, disabled by default
  -> optional private VPC endpoints, enabled by default
  -> S3 gateway endpoint when VPC endpoints are enabled
  -> outputs consumed by backend-stateful-dependencies and eks-runtime
```

The default mode is optimized for the first private EKS smoke:

```text
enable_nat_gateway   = false
enable_vpc_endpoints = true
```

This keeps broad private subnet internet egress explicit while still giving private EKS nodes a path for ECR image pull and required AWS API calls through private endpoints.

## Apply order for live validation

This repository still does not run `terraform apply` automatically. For a live validation, the operator runs Terraform manually and records outputs.

Recommended order:

```text
1. aws-runtime-network
2. backend-runtime-dependencies
3. backend-stateful-dependencies
4. eks-runtime
5. backend image publish
6. AWS runtime input bundle
7. AWS runtime deployment package
8. manual kubectl apply
9. rollout smoke
10. evidence collection
```

## 1. Create the network tfvars

Copy the example file outside committed source or to a local ignored tfvars file.

```bash
cp infra/terraform/envs/aws-runtime-network/terraform.tfvars.example \
  /tmp/terraformers-aws-runtime-network.tfvars
```

Review the CIDR ranges and region before applying.

## 2. Run Terraform manually

```bash
cd infra/terraform/envs/aws-runtime-network
terraform init
terraform plan \
  -var-file=/tmp/terraformers-aws-runtime-network.tfvars \
  -out=/tmp/terraformers-aws-runtime-network.tfplan
terraform apply /tmp/terraformers-aws-runtime-network.tfplan
```

Capture outputs:

```bash
terraform output -json > /tmp/aws-runtime-network-output.json
```

## 3. Feed network outputs into the next Terraform stacks

Use these outputs in `backend-stateful-dependencies`:

```text
vpc_id                 = output.vpc_id
private_subnet_ids     = output.private_subnet_ids
allowed_database_cidr_blocks = output.private_subnet_cidr_blocks
```

For the first disposable live validation, allowing MariaDB from the private subnet CIDRs is acceptable because the subnets are dedicated to the runtime validation environment. A later hardening pass can replace this with a narrower security-group-based boundary after the EKS node or pod security group boundary is finalized.

Use these outputs in `eks-runtime`:

```text
vpc_id             = output.vpc_id
private_subnet_ids = output.private_subnet_ids
```

## NAT versus VPC endpoints

### Default: VPC endpoints enabled, NAT disabled

The default configuration creates private endpoints for:

```text
ECR API
ECR Docker registry
CloudWatch Logs
Secrets Manager
SQS
STS
S3 gateway endpoint
```

This is intended for private EKS worker nodes without broad outbound internet access.

### Optional NAT gateway

Set `enable_nat_gateway = true` only when broader private subnet egress is intentionally required.

```hcl
enable_nat_gateway = true
```

NAT gateway introduces hourly and data-processing cost, so it should be treated as a conscious live-validation decision rather than a default scaffold behavior.

## Outputs

Important outputs:

```text
vpc_id
vpc_cidr_block
public_subnet_ids
private_subnet_ids
private_subnet_cidr_blocks
eks_cluster_name_hint
nat_gateway_enabled
vpc_endpoints_enabled
interface_vpc_endpoint_ids
s3_gateway_vpc_endpoint_id
```

## Stop condition

This step is complete when:

```text
- Terraform Static Verification includes aws-runtime-network
- aws-runtime-network validates statically
- the scaffold can provide vpc_id and private_subnet_ids to backend-stateful-dependencies and eks-runtime
- NAT gateway remains explicit and disabled by default
- no Kubernetes apply, ALB ingress, public backend exposure, or adapter enablement is added
```

After this network scaffold is merged, the next meaningful step is not another checklist PR. The next step is to run a controlled AWS live validation with explicit user approval for each manual Terraform apply and manual Kubernetes apply boundary.
