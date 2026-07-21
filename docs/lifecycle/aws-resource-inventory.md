# AWS Resource Inventory for Closure

## 1. Purpose

This document is the authoritative inventory for removing and later recreating the Terraformers-modernization AWS environment.

It must answer five questions for every resource group:

1. Who created it?
2. Is it represented in Terraform state?
3. What must be removed before it?
4. What data or evidence must be retained?
5. What source recreates it?

A Terraform state address list is necessary but not sufficient. Kubernetes controllers, Argo CD, service data, object versions, Secret values, users, logs, and GitHub configuration are managed outside Terraform state.

## 2. Evidence sources

Use each source once and merge the results into the inventory table.

| Evidence source | Purpose | Mutation allowed |
|---|---|---|
| `AWS Terraform State Inventory` workflow | Sanitized state addresses and counts for seven remote-state components | No |
| Terraform state component metadata | Confirms which root owns each resource | No |
| `kubectl get` and Argo CD read-only inspection | Finds desired objects, owner references, image digests, Ingress, and generated load-balancer owners | No |
| AWS read-only inspection | Finds controller-generated, data-only, scheduled-deletion, log, image, and object-version resources | No |
| GitHub repository/environment inspection | Records variable and secret names and approval environments | No |
| Existing deployment and operations evidence | Records recreation and rollback source | No |

Do not upload raw tfstate, Terraform outputs, kubeconfig, object contents, Secret values, environment variables, Cognito tokens, prompts, source images, retrieved text, generated Terraform, or account-specific credentials.

## 3. Terraform state components

The state inventory workflow must inspect these exact components:

| State component | Terraform root | Expected responsibility |
|---|---|---|
| `bootstrap` | `infra/terraform/bootstrap/aws-live-foundation` | State bucket and GitHub OIDC plan/apply foundation |
| `network` | `infra/terraform/envs/aws-runtime-network` | VPC, subnets, routes, NAT/IGW, endpoints, network outputs |
| `runtime-dependencies` | `infra/terraform/envs/backend-runtime-dependencies` | ECR, SQS, application buckets, runtime Secrets and related IAM |
| `stateful-dependencies` | `infra/terraform/envs/backend-stateful-dependencies` | RDS, Cognito, stateful security boundaries |
| `eks-runtime` | `infra/terraform/envs/eks-runtime` | EKS, node group, IRSA, CloudWatch add-on, dashboard and alarms |
| `frontend-delivery` | `infra/terraform/envs/frontend-delivery` | Private frontend S3/CloudFront delivery and VPC origin resources |
| `rag-runtime` | `infra/terraform/envs/rag-runtime` | AOSS, private ingestion executor, corpus storage and RAG IAM/network |

The workflow records addresses only. Resource IDs, ARNs, attributes, outputs, lineage, and raw state are not repository evidence.

## 4. Management classification

Every inventory row must use one of the following classifications.

| Classification | Meaning | Delete owner |
|---|---|---|
| `terraform` | Resource is represented in one remote Terraform state component | Reviewed destroy plan and apply |
| `gitops` | Resource is reconciled from a Git manifest by Argo CD | Git/Argo CD application removal |
| `kubernetes-operator` | Resource is produced by a Kubernetes operator or Helm release | Custom resource or release removal |
| `controller-generated` | AWS resource is produced from a Kubernetes owner object | Delete owner object, then verify AWS deletion |
| `data-only` | Mutable content is not represented as a Terraform resource | Service API or bounded cleanup step |
| `bootstrap` | Required to run the remaining Terraform workflow | Delete last |
| `external-config` | GitHub variables, secrets, approvals, or local operator inputs | Separate non-AWS decision |

## 5. Baseline inventory matrix

Replace `PENDING_LIVE_INVENTORY` only after the read-only inventory pass. Do not infer existence from source code alone.

| Resource group | Classification | Terraform state | Current live state | Delete prerequisite | Delete owner | Recreation source | Retention decision | Residual check |
|---|---|---|---|---|---|---|---|---|
| Terraform state bucket and lock objects | bootstrap | `bootstrap` or external bootstrap record | PENDING_LIVE_INVENTORY | all other states removed; versions exported only if approved | final bootstrap procedure | foundation bootstrap root | retain export / delete all versions | bucket and versions absent |
| GitHub OIDC provider | bootstrap | `bootstrap` | PENDING_LIVE_INVENTORY | all GitHub Actions AWS work complete | final bootstrap procedure | foundation bootstrap root | none | provider absent or documented shared reuse |
| Terraform plan/apply roles and policies | bootstrap | `bootstrap` | PENDING_LIVE_INVENTORY | all runtime and bootstrap operations complete | final bootstrap procedure | foundation bootstrap root | none | project roles/policies absent |
| VPC, subnets, routes, NAT, IGW | terraform | `network` | PENDING_LIVE_INVENTORY | EKS, AOSS endpoint, RDS, ALB, VPC origins and endpoints removed | Terraform destroy | network root | none | VPC and dependent ENIs absent |
| Gateway/interface endpoints | terraform | `network` or `rag-runtime` | PENDING_LIVE_INVENTORY | dependent services stopped | Terraform destroy | corresponding root | none | endpoints absent |
| ECR repositories | terraform | `runtime-dependencies` | PENDING_LIVE_INVENTORY | deployments no longer require image; images purged if required | data cleanup + Terraform destroy | runtime-dependencies root + image workflow | retain digest evidence only | repositories and images absent |
| Upload/result/frontend/corpus S3 buckets | terraform plus data-only | multiple | PENDING_LIVE_INVENTORY | delivery stopped; object versions and delete markers handled | data cleanup + Terraform destroy | Terraform roots + delivery/ingestion workflows | explicit per bucket | buckets and all versions absent |
| SQS queues | terraform | `runtime-dependencies` | PENDING_LIVE_INVENTORY | Backend/analysis stopped | Terraform destroy | runtime-dependencies root | none | queues absent |
| Secrets Manager containers | terraform plus data-only | `runtime-dependencies` / `stateful-dependencies` | PENDING_LIVE_INVENTORY | ExternalSecret and workloads stopped | Terraform destroy or explicit deletion mode | Terraform roots + approved initialization | retain names/source only; never values | no active or scheduled project Secret remains |
| RDS instance, subnet/security groups, managed credential | terraform plus stateful data | `stateful-dependencies` | PENDING_LIVE_INVENTORY | Backend stopped; snapshot decision approved | Terraform destroy | stateful-dependencies root + migrations | snapshot retain/delete decision | instance, snapshots and project groups absent |
| Cognito user pool/client and test users | terraform plus data-only | `stateful-dependencies` | PENDING_LIVE_INVENTORY | frontend/backend stopped | Terraform destroy | stateful-dependencies root + manual test-user procedure | no token/user evidence | pool/client/users absent |
| EKS cluster and managed node group | terraform | `eks-runtime` | PENDING_LIVE_INVENTORY | GitOps apps, workloads, Ingress, operators, generated ALB, add-ons removed | Terraform destroy | eks-runtime root | none | cluster/node group absent |
| EKS managed add-ons and CloudWatch observability | terraform | `eks-runtime` | PENDING_LIVE_INVENTORY | final telemetry evidence frozen | Terraform destroy | eks-runtime root | logs/trace retention decision | add-ons absent |
| Backend IRSA and observability IRSA | terraform | `eks-runtime` | PENDING_LIVE_INVENTORY | workloads/add-on removed | Terraform destroy | eks-runtime root | none | roles/policies absent |
| Argo CD Helm release and Application | kubernetes-operator/gitops | none | PENDING_LIVE_INVENTORY | auto-sync disabled; desired-state evidence frozen | Helm/kubectl operator step | pinned chart values and application manifest | retain Git history only | namespace/resources absent |
| Backend Deployment, Service and ConfigMap | gitops | none | PENDING_LIVE_INVENTORY | delivery frozen | Argo CD application removal | GitOps overlay and immutable image workflow | retain digest evidence | objects absent |
| External Secrets operator, SecretStore and ExternalSecret | kubernetes-operator | none | PENDING_LIVE_INVENTORY | Backend stopped; Secret evidence frozen | Helm/custom-resource removal | pinned operator procedure and manifests | never retain Secret data | resources and generated Secret absent |
| AWS Load Balancer Controller and Ingress | kubernetes-operator | partial IRSA in Terraform | PENDING_LIVE_INVENTORY | CloudFront origin disabled/removed | Ingress then controller removal | controller chart/IRSA and Ingress manifest | none | Ingress/controller absent |
| Internal ALB, target groups and generated rules | controller-generated | none | PENDING_LIVE_INVENTORY | CloudFront no longer references origin | delete Ingress; wait for controller cleanup | Ingress/controller manifests | none | ALB/TG/generated SG resources absent |
| CloudFront distribution, OAC, function and VPC origin | terraform | `frontend-delivery` | PENDING_LIVE_INVENTORY | delivery frozen; distribution disabled as required | Terraform destroy | frontend-delivery root | retain domain/screenshots only | distribution and origins absent |
| AOSS collection, policies and private endpoint | terraform | `rag-runtime` | PENDING_LIVE_INVENTORY | Backend retrieval and ingestion stopped | Terraform destroy | rag-runtime root | corpus is recreated from repository v2 | collection/policies/endpoint absent |
| AOSS index and vector documents | data-only | none or service-created | PENDING_LIVE_INVENTORY | ingestion stopped | AOSS API or collection deletion | committed corpus v2 + ingestion workflow | retain sanitized receipt only | no project index/document remains |
| CodeBuild ingestion project and role | terraform | `rag-runtime` | PENDING_LIVE_INVENTORY | no build running | Terraform destroy | rag-runtime root | retain run ID evidence only | project/role absent |
| CloudWatch log groups, metrics, dashboard, alarms and X-Ray traces | mixed | `eks-runtime` plus service-generated | PENDING_LIVE_INVENTORY | final evidence frozen | Terraform destroy + explicit log cleanup | eks-runtime root and service runtime | explicit retention period | project dashboard/alarms/log groups absent |
| GitHub environments, variables and encrypted secrets | external-config | none | PENDING_LIVE_INVENTORY | none for AWS runtime teardown | repository setting decision | redeploy runbook | retain for redeploy or remove deliberately | documented final decision |

## 6. Required live inventory fields

Each populated resource group must record:

- exact service/resource group name, not secret values;
- region and account verification outcome;
- Terraform state component or Kubernetes owner;
- source commit or manifest path;
- current status;
- data volume/count where useful and safe;
- deletion blocker;
- recreation method;
- retention decision;
- residual query.

Do not record raw resource policies when an address and policy owner are enough.

## 7. Read-only state inventory execution

After the closure PR is merged, run the workflow from the integration branch with an exact expected commit:

```bash
gh workflow run "AWS Terraform State Inventory" \
  --repo siamese-lang/Terraformers-modernization \
  --ref agent/rdb-domain-realignment \
  -f execute_read_only_inventory=true \
  -f expected_aws_account_id="$EXPECTED_AWS_ACCOUNT_ID" \
  -f expected_head_sha="$EXPECTED_HEAD_SHA"
```

The artifact is allowed to contain only:

- component name;
- state object presence;
- Terraform version and serial;
- sanitized resource addresses;
- resource type counts;
- execution commit and account/region verification flags.

## 8. Completion criteria

Closure Gate 1 is complete only when:

- all seven state components are accounted for;
- every Kubernetes object has an owner and deletion order;
- every controller-generated AWS resource has a Kubernetes owner;
- every data-only resource has a retention and cleanup decision;
- bootstrap resources are explicitly separated from runtime resources;
- no unexplained project resource remains in the AWS read-only scan;
- the inventory can drive both `aws-teardown-runbook.md` and `aws-redeploy-runbook.md` without relying on memory.