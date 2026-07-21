# Kubernetes, GitOps, and Internal ALB Inventory Result

## 1. Execution identity

This result records the bounded read-only inventory performed after Terraform state inventory completion.

| Field | Value |
|---|---|
| Integration revision | `c5ed6f98a325a469ba9b29f6dec6f6c030b5f4ab` |
| Kubernetes namespace | `terraformers-runtime` |
| AWS region | `ap-northeast-2` |
| Mutation | None |
| Terraform plan/apply/destroy | None |
| Kubernetes apply/delete/patch | None |
| AWS create/update/delete | None |

## 2. GitOps and Backend runtime

| Item | Verified value |
|---|---|
| Argo CD Application sync | `Synced` |
| Argo CD Application health | `Healthy` |
| Argo CD revision | `c5ed6f98a325a469ba9b29f6dec6f6c030b5f4ab` |
| Desired Backend image | `024863981627.dkr.ecr.ap-northeast-2.amazonaws.com/terraformers-backend@sha256:2f4a177a06d1e64819b06240a441e619105980e43dea04b3f4709a86e2d95c73` |
| Running Pod image ID | same immutable digest |
| Backend Pod Ready | `true` |
| Backend Pod restarts | `0` |
| Runtime Deployments | `1` |
| Runtime Services | `1` |
| Runtime Ingresses | `1` |

This proves Git desired state, Deployment image, and Pod runtime image remained aligned after documentation-only integration commits.

## 3. Kubernetes operator inventory

| Owner | Verified state | Deletion role |
|---|---|---|
| External Secrets Operator | `external-secrets: 1/1` | Remove ExternalSecret/SecretStore and generated Secret before operator teardown |
| AWS Load Balancer Controller | `aws-load-balancer-controller: 1/1` | Remove Backend Ingress and wait for ALB, target group, listeners, and generated rules to disappear |
| Argo CD Backend Application | `Synced/Healthy` | Suspend automated reconciliation, delete managed Backend resources, then remove Application |
| Argo CD Application Controller | Not evaluated by the Deployment helper | Inspect as StatefulSet during the final owner inventory; blank helper output is not evidence of absence |

The command used a Deployment-only helper for the Argo CD controller. In the pinned non-HA Argo CD installation, the Application Controller is expected to be a StatefulSet. Therefore `argocd_controller=` is a query-shape limitation, not a runtime failure.

## 4. External Secrets resources

| Resource type | Live count |
|---|---:|
| ExternalSecret | `1` |
| SecretStore | `1` |

The generated Kubernetes Secret contents were not inspected or recorded.

Deletion boundary:

1. stop Backend workload;
2. delete or suspend ExternalSecret reconciliation;
3. remove generated Kubernetes Secret;
4. remove SecretStore/ExternalSecret;
5. remove External Secrets Operator only after no project custom resource remains;
6. handle the AWS Secrets Manager container and versions through their separate Terraform/data-owner path.

## 5. Internal ALB inventory

| Item | Verified value |
|---|---|
| Ingress hostname | `internal-terraformers-dev-origin-730782881.ap-northeast-2.elb.amazonaws.com` |
| ALB found | `true` |
| ALB scheme | `internal` |
| Target groups | `1` |
| Healthy targets | `1` |
| Unhealthy targets | `0` |

This confirms the internal ALB is a live controller-generated AWS resource rather than a Terraform-managed resource.

The owner chain is:

```text
Git/manifest
  -> Kubernetes Ingress
  -> AWS Load Balancer Controller
  -> internal ALB
  -> listener/rules
  -> target group
  -> Pod IP target
```

The ALB must not be deleted directly as the normal teardown path. The correct sequence is:

1. ensure CloudFront no longer references the VPC origin;
2. delete the Backend Ingress owner;
3. wait for the controller to remove the ALB and dependent resources;
4. verify the ALB, listeners, target group, registrations, generated security-group rules, and load-balancer ENIs are absent;
5. only then remove the controller and EKS cluster.

## 6. Closure findings

Confirmed:

- Argo CD desired state is current and healthy;
- Backend desired and runtime image digests match;
- Backend Pod is healthy with no restart;
- one runtime Deployment, Service, and Ingress own the application path;
- External Secrets and AWS Load Balancer Controller are healthy;
- one ExternalSecret and one SecretStore exist;
- the controller-generated ALB is internal and has one healthy target;
- no public Backend ALB was observed;
- Kubernetes and ALB inventory caused no mutation.

Remaining owner details before Closure Gate 1 completes:

- Argo CD Helm release and StatefulSet/controller resource counts;
- namespaces and any temporary Jobs/Pods that must not survive teardown;
- ServiceAccounts and IRSA annotations for Backend, External Secrets, and Load Balancer Controller;
- generated Secret existence without reading its value;
- exact ALB listener/rule and generated security-group/ENI counts for residual checks.

These details can be captured together with the final data-only AWS inventory. No new architecture investigation is required.

## 7. Next inventory boundary

The remaining Gate 1 work is now limited to counts and ownership for:

- ECR images;
- versioned S3 objects/delete markers/multipart uploads;
- SQS messages;
- active and pending-deletion Secrets;
- RDS snapshots, retained backups, and managed credential Secret;
- Cognito users;
- AOSS index/document and CodeBuild run state;
- CloudWatch log groups and retention;
- GitHub OIDC provider ownership and GitHub configuration names;
- final Kubernetes owner counts listed above.

The next pass must remain summary-oriented and read-only.