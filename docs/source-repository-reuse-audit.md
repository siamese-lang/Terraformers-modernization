# Source Repository Reuse Audit

## Purpose

This audit fixes the working rule for Terraformers modernization: do not recreate the system from scratch. The modernization repository must reuse and refactor the original Terraformers application, original Infra-code infrastructure, and the first RDB refactor where possible.

This document was created after closing PR #25 without merge because that PR added a new AWS runtime network scaffold before the source repositories were fully reviewed.

## Source repositories

```text
Application source:
- AWS-Terraformers/Terraformers

Original infrastructure source:
- AWS-Terraformers/Infra-code

First RDB refactor source:
- siamese-lang/rdb-refactor

Current modernization target:
- siamese-lang/Terraformers-modernization
```

## Current decision

```text
PR #25 must stay closed.
Do not merge the newly written aws-runtime-network scaffold as-is.
Replace it with a source-reuse-first infrastructure modernization plan.
```

Reason:

```text
AWS-Terraformers/Infra-code already contains reusable network and EKS modules.
siamese-lang/rdb-refactor already contains RDS-centered infrastructure work and prior reuse analysis.
```

## AWS-Terraformers/Terraformers review

### Reusable application concepts

The original application preserves the product identity that modernization must keep:

```text
architecture image upload
-> project creation
-> generated Terraform code metadata
-> project tree
-> main.tf file read/update
-> public projects/comments
```

The original backend still contains DynamoDB/S3-centered service logic. Reuse the product behavior and API intent, not the DynamoDB implementation as-is.

Reusable behavior:

```text
- project creation with image URL
- project visibility/public project listing
- Terraform main.tf file metadata
- project tree shape
- file/folder node behavior
- S3-backed file content read/update pattern
- Cognito-authenticated user boundary
```

Must not reuse as-is:

```text
- user-provided AWS access key storage/update API
- DynamoDB table access as the new persistence baseline
- broad exception swallowing and mixed table-name hardcoding
- runtime AWS credential handling that conflicts with IRSA/OIDC boundaries
```

## AWS-Terraformers/Infra-code review

### Network module

Original reusable file:

```text
modules/network/main.tf
```

Reusable concepts:

```text
- VPC creation
- public subnet creation
- private subnet creation
- Kubernetes public subnet tag: kubernetes.io/role/elb
- Kubernetes private subnet tag: kubernetes.io/role/internal-elb
- kubernetes.io/cluster/<cluster-name>=shared tagging
- Internet Gateway and route tables
- NAT gateway model
- S3 VPC endpoint
- Bedrock runtime interface endpoint concept
```

Must modify before porting:

```text
- remove test_vpc/test_subnet naming
- parameterize region instead of hardcoding us-west-2 endpoint service names
- make NAT explicit and cost-aware
- avoid creating one NAT gateway per subnet by default for disposable validation
- align outputs with current modernization names: private_subnet_ids, public_subnet_ids, vpc_id
- add typed variables and validation
- keep public backend exposure out of the first private smoke
```

### EKS module

Original reusable file:

```text
modules/eks/main.tf
```

Reusable concepts:

```text
- EKS cluster role
- EKS cluster resource
- private subnet-based cluster/node group placement
- OIDC provider for IRSA
- worker node role
- managed node group
- ECR read-only policy for nodes
- kubeconfig update sequencing as operator concept
```

Must modify before porting:

```text
- remove broad S3 full-access policy from the EKS cluster role
- remove DynamoDB node policy dependency
- replace local-exec kubeconfig side effect with explicit operator/runbook step
- keep node size and count explicit for live validation cost control
- keep cluster public endpoint CIDR-restricted
- align service account/IRSA role with current backend runtime contract
```

### Backend app / exposure module

Original reusable file:

```text
modules/backend-app/main.tf
```

Reusable concepts:

```text
- Kubernetes ServiceAccount with IRSA annotation
- backend Service abstraction
- NLB/public exposure pattern for a later stage
```

Must not use in the first live validation:

```text
- internet-facing LoadBalancer exposure
- certificate/domain-dependent NLB path
```

Use later only after private EKS smoke passes.

### env/dev composition

Original reusable file:

```text
env/dev/main.tf
```

Reusable concepts:

```text
network -> sg -> eks -> backend_app -> argocd composition
S3/CloudFront/frontend deployment structure
Bedrock/AOSS conceptual dependency path
ArgoCD GitOps deployment concept
```

Must modify before porting:

```text
- do not restore application DynamoDB as the main persistence model
- do not copy hardcoded image values
- do not copy hardcoded domain/certificate assumptions
- do not use auto-approve apply as a default path
- do not use static AWS keys or cross-repository mutation patterns
```

## siamese-lang/rdb-refactor review

### Prior reuse inventory

Reusable file:

```text
docs/original-deployment-automation-reuse-inventory.md
```

This document is now a governing source for modernization. It already separated reusable deployment concepts from unsafe legacy patterns.

Reuse:

```text
- Terraform fmt/init/validate/plan structure
- Terraform output extraction pattern
- EKS kubeconfig setup sequencing as approved/operator stage
- ArgoCD GitOps structure
- backend Deployment/HPA/envFrom concept
- frontend build, S3 sync, CloudFront invalidation concepts
```

Must not reuse as-is:

```text
- long-lived AWS key direct usage
- terraform apply -auto-approve in default flows
- application DynamoDB output restoration
- hardcoded runtime/domain values
- AWS key injection into Kubernetes secrets
- GH_PAT cross-repository workflow mutation
```

### RDS and datasource contract

Reusable files:

```text
Infra-code-main/Infra-code-main/modules/rds-mariadb/main.tf
Infra-code-main/Infra-code-main/modules/rds-mariadb/outputs.tf
app/Terraformers-main/backend/mini/src/main/resources/application-prod.properties
app/Terraformers-main/backend/mini/src/main/resources/db/migration/V20260523_000__initial_core_schema.sql
```

Reuse:

```text
- RDS for MariaDB module concept
- DB subnet group and RDS security group model
- SG-based DB ingress model
- manage_master_user_password=true
- JDBC URL output
- Flyway migration source of truth
- production datasource via SPRING_DATASOURCE_URL / USERNAME / PASSWORD
- ddl-auto=validate runtime contract
```

Modify:

```text
- align output names with current backend-stateful-dependencies
- decide whether current modernization env keeps inline RDS resource or imports/refactors the rdb-refactor module style
- ensure password value is injected only through Secrets Manager / Kubernetes Secret / ExternalSecret path, never committed
```

## Current modernization repository state

Already merged and usable:

```text
- backend product API contract tests
- Kubernetes base/local/AWS runtime scaffold
- Terraform backend-runtime-dependencies
- Terraform backend-stateful-dependencies
- Terraform eks-runtime
- runtime Secret render path
- AWS runtime manifest render path
- deploy preflight
- rollout smoke
- input bundle builder
- deployment package builder
- evidence collection path
```

Problem found:

```text
The current modernization repository has runtime scaffolds, but the next infrastructure work must be reconciled with source repositories before adding new Terraform.
```

## PR #25 decision

```text
Close without merge: done.
Replacement required: yes.
```

Why:

```text
PR #25 added a new network scaffold before reusing Infra-code modules/network and rdb-refactor infrastructure work.
```

## Replacement implementation direction

The next implementation PR should be one of these, in order:

### Option A: source-reused network module refactor

```text
Goal:
Refactor the current AWS runtime network requirement using the original Infra-code network module concepts.

Reuse:
- modules/network VPC/subnet/tag/IGW/route table concepts
- output contract: vpc_id, public_subnet_ids, private_subnet_ids

Modify:
- type variables
- region-parameterized endpoints
- default NAT disabled or explicitly opt-in
- cost-aware validation profile
- current naming/tag convention

Add:
- only missing outputs/validation needed by backend-stateful-dependencies and eks-runtime
```

### Option B: RDS module alignment

```text
Goal:
Align backend-stateful-dependencies with rdb-refactor RDS module and runtime datasource contract.

Reuse:
- rdb-refactor rds-mariadb module
- manage_master_user_password=true
- jdbc_url output
- Flyway/ddl-auto=validate contract

Modify:
- output names to fit current input bundle builder
- secret injection boundary
```

### Option C: GitOps/backend-app alignment

```text
Goal:
Refactor Kubernetes backend runtime manifest against original backend-app and rdb-refactor GitOps contract.

Reuse:
- ServiceAccount IRSA annotation concept
- backend Deployment/envFrom/Secret pattern
- ArgoCD GitOps concept

Modify:
- no public LoadBalancer in private smoke
- image URI must be immutable
- RDS/Flyway datasource contract
```

## Hard boundaries

```text
Do not:
- create new infrastructure from scratch without source review
- reintroduce DynamoDB as primary app persistence
- add Terraform execution UI/API
- add auto-approve apply in default CI
- inject static AWS keys into application secrets
- expose backend publicly before private smoke succeeds
```

## Working rule for every next PR

Every PR must include:

```text
Source review:
- AWS-Terraformers/Terraformers checked files
- AWS-Terraformers/Infra-code checked files
- siamese-lang/rdb-refactor checked files

Reuse:
- source structures reused directly or conceptually

Modify:
- source structures changed for modernization

Add:
- only genuinely missing code

Exclude:
- explicit out-of-scope items

Validation:
- static verification or focused test

Stop condition:
- exact condition for merge readiness
```
