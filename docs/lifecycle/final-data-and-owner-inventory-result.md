# Final Data and Owner Inventory Result

## 1. Scope

This document closes the remaining non-Terraform inventory boundary for Terraformers-modernization.

The inventory was read-only. It did not create, update, delete, patch, apply, or destroy any AWS, Kubernetes, Argo CD, Terraform, image, frontend, corpus, or GitHub resource.

Integration revision at the start of this pass:

```text
b3e3a672dc65c7a712a20459b3d8f1c31ca62861
```

## 2. Kubernetes owners

| Item | Live result | Teardown implication |
|---|---|---|
| Argo CD Application Controller | StatefulSet `argocd-application-controller` `1/1` | Remove Backend Application and managed resources before uninstalling Argo CD |
| Argo CD Deployments | 4 total | `argocd-redis`, `argocd-repo-server`, and `argocd-server` are `1/1`; ApplicationSet controller is intentionally `0/0` |
| Project Helm releases | 3 | `argocd/argocd`, `kube-system/aws-load-balancer-controller`, `external-secrets/external-secrets` |
| IRSA ServiceAccounts | 5 | CloudWatch operator, CloudWatch agent, Load Balancer Controller, Backend, and External Secrets identities must remain until their owners are removed |
| ExternalSecret | `terraformers-runtime/terraformers-backend-runtime`, Ready `True`, reason `SecretSynced` | Stop Backend, stop reconciliation, remove generated Secret, then remove custom resources/operator |
| Generated Kubernetes Secret | `terraformers-backend-runtime-secrets` exists | Never export values; remove after Backend is stopped |
| Project Jobs | 0 | No active Job blocks teardown |
| Unowned runtime Pods | 0 | No temporary standalone Pod blocks namespace deletion |

## 3. Internal ALB dependencies

| Item | Count |
|---|---:|
| Internal ALB | 1 |
| Listener | 1 |
| Listener rules | 2 |
| Target group | 1 |
| Healthy targets | 1 |
| Unhealthy targets | 0 |
| ALB security groups | 2 |
| Load-balancer network interfaces | 2 |

Owner chain:

```text
CloudFront VPC origin
  -> Kubernetes Ingress
  -> AWS Load Balancer Controller
  -> internal ALB
  -> listener and rules
  -> target group
  -> Pod IP target
```

The normal deletion path is:

1. remove the CloudFront VPC-origin reference;
2. delete the Ingress owner;
3. wait for controller reconciliation;
4. verify the ALB, listener, rules, target group, security-group dependencies, and ENIs are absent;
5. uninstall the controller only after the generated AWS resources are gone.

## 4. ECR

| Item | Live count | Retention decision |
|---|---:|---|
| Terraformers ECR repositories | 1 | Delete after Backend is stopped |
| Image details | 20 | Retain only the final immutable digest string in Git evidence; delete all images and repository data |

Final retained evidence digest:

```text
sha256:2f4a177a06d1e64819b06240a441e619105980e43dea04b3f4709a86e2d95c73
```

## 5. Versioned S3 data

All five project buckets have versioning enabled. No multipart upload is active.

| Bucket | Versions | Delete markers | Multipart uploads | Owner | Retention decision |
|---|---:|---:|---:|---|---|
| `terraformers-dev-rag-corpus-024863981627` | 7 | 0 | 0 | `rag-runtime` plus corpus workflow | Corpus source remains in Git; purge all bucket versions before destroy |
| `terraformers-dev-result-024863981627` | 21 | 0 | 0 | `runtime-dependencies` plus application data | Retain only sanitized portfolio summaries; purge all versions |
| `terraformers-dev-upload-024863981627` | 35 | 0 | 0 | `runtime-dependencies` plus application data | Do not retain source images in AWS; purge all versions |
| `terraformers-modernization-024863981627-apne2-state` | 175 | 126 | 0 | bootstrap | Delete last, after all runtime states and residual checks; purge all versions and markers |
| `terraformers-modernization-dev-frontend-024863981627` | 70 | 30 | 0 | `frontend-delivery` plus delivery workflow | Rebuildable from source; purge all versions and markers |
| **Total** | **308** | **156** | **0** | — | Zero project S3 versions after teardown |

Raw Terraform state will not be copied into repository evidence. An external encrypted state export is not required for the zero-state redeployment model.

## 6. SQS

| Queue | Ownership | Live messages | Decision |
|---|---|---:|---|
| `terraformers-ai-log` | Terraform-managed runtime dependency | 0 | Delete through `runtime-dependencies` destroy |
| `terraformers-terraform-log` | Terraform-managed runtime dependency | 0 | Delete through `runtime-dependencies` destroy |
| `terraformers-ai-log-live-smoke` | Legacy live-smoke resource outside current state | 0 | Delete through explicit residual cleanup |
| `terraformers-terraform-log-live-smoke` | Legacy live-smoke resource outside current state | 0 | Delete through explicit residual cleanup |

Visible, in-flight, and delayed message totals were all zero.

## 7. Secrets Manager and External Secrets

| Item | Live count/state | Decision |
|---|---|---|
| Active project Secrets | 2 | Delete after workloads and ExternalSecret reconciliation stop |
| Pending-deletion Secrets | 0 | No existing name-reuse blocker |
| Backend runtime Secret container | Terraform-managed | Final deletion should use force deletion to avoid redeployment name conflict |
| RDS managed master Secret | 1 | Removed with the RDS managed-password lifecycle; verify residual absence |
| Generated Kubernetes Secret | Ready and present | Never export values; remove before operator teardown |

The two active Secrets are explained by the Terraform-managed Backend runtime Secret and the RDS-managed master credential Secret. No unexplained Secret remains.

## 8. RDS

| Item | Live result | Retention decision |
|---|---|---|
| DB instances | 1 | Delete after Backend stops |
| Deletion protection enabled | 0 | No protection toggle is required |
| Manual snapshots | 0 | No manual snapshot cleanup exists before deletion |
| Automated backup records | 1 | Do not retain after final teardown |
| Managed master Secret | 1 | Delete with the RDS lifecycle and verify separately |
| Final snapshot | Not yet created | Skip final snapshot; schema is recreated by Flyway and portfolio evidence does not require data retention |

The closure objective is zero project AWS resources, so no RDS snapshot or retained automated backup remains after teardown.

## 9. Cognito

| User pool | Ownership | Users | Decision |
|---|---|---:|---|
| `terraformers-modernization-dev-users` | Terraform-managed current pool | 0 | Delete through `stateful-dependencies` destroy |
| `terraformers-modernization-live-smoke-users` | Legacy live-smoke pool outside current state | 0 | Delete through explicit residual cleanup |

No Cognito user or token data needs preservation.

## 10. AOSS and CodeBuild

| Item | Live result | Decision |
|---|---|---|
| AOSS collections | 1 |
| Active AOSS collections | 1 |
| Verified vector documents | 128 from the committed corpus-v2 receipt |
| CodeBuild projects | 1 |
| Active CodeBuild builds | 0 |

Retention decision:

- delete the index, documents, collection, endpoint, and policies;
- retain the curated corpus v2 and ingestion source in Git;
- retain only sanitized document-count and workflow evidence;
- recreate the index through the documented ingestion workflow after redeployment.

## 11. CloudWatch and X-Ray

| Item | Live result | Retention decision |
|---|---:|---|
| Terraformers log groups | 8 | Delete all after final evidence is frozen |
| Log groups without retention policy | 8 | No indefinite logs remain after teardown |
| Stored bytes | 529,613,946 bytes, about 505 MiB | Retain only sanitized evidence summaries in Git |
| Terraform-managed dashboard | 1 | Delete through `eks-runtime` |
| Terraform-managed alarms | 3 | Delete through `eks-runtime` |
| X-Ray | No separate persistent project resource requiring destroy | Traces expire by service retention; verify no project-owned group/resource remains |

The absence of retention configuration is a cost and lifecycle finding, but no new retention-policy change is required before imminent teardown.

## 12. GitHub OIDC ownership

| Item | Result |
|---|---|
| GitHub OIDC providers in account | 1 |
| Roles trusting the provider | 5 |
| Terraformers roles among trusting roles | 5 |

Trusting roles:

- `terraformers-dev-backend-image-publisher`;
- `terraformers-dev-frontend-delivery`;
- `terraformers-dev-refs-corpus-ingestion`;
- `terraformers-live-terraform-apply`;
- `terraformers-live-terraform-plan`.

Conclusion:

- the provider is outside Terraform state;
- every current trusting role is Terraformers-specific;
- classify it as a project-dedicated external bootstrap resource;
- retain it until all GitHub Actions AWS work is complete;
- delete it from an independent administrator or CloudShell identity after the five roles are removed.

## 13. GitHub configuration

GitHub configuration is not an AWS resource and will be retained for future redeployment.

Environments:

- `aws-backend-image-publish`;
- `aws-live-apply`;
- `aws-live-plan`;
- `aws-rag-corpus-ingestion`;
- `frontend-delivery`.

Repository variables:

- `REACT_APP_AWS_REGION`;
- `REACT_APP_COGNITO_USER_POOL_CLIENT_ID`;
- `REACT_APP_COGNITO_USER_POOL_ID`.

Repository-level encrypted secrets: none.

Environment variables and secret names are already recorded in the redeployment runbook and inventory output. Values remain encrypted and are not copied into documentation.

Decision:

- retain environments, approval rules, variables, and encrypted tfvars through AWS teardown;
- update values only when a future redeployment receives new resource identifiers;
- do not remove GitHub configuration as part of the AWS zero-resource proof.

## 14. Final retention decisions

| Data/resource | Decision |
|---|---|
| ECR images | Delete all; retain final digest string only |
| S3 current and noncurrent versions | Delete all after sanitized evidence is frozen |
| S3 delete markers | Delete all |
| Terraform state versions | Delete last; no repository copy |
| RDS final snapshot | Skip |
| RDS manual/automated backups | Leave none after teardown |
| Secrets Manager recovery | Force delete at the final owner step to avoid same-name redeploy blocking |
| Cognito users/pools | Delete all current and legacy-smoke resources |
| AOSS index/documents | Delete; recreate from corpus v2 |
| CloudWatch logs | Delete all eight groups after evidence freeze |
| X-Ray traces | No explicit delete API step; allow service retention expiration |
| GitHub environments/variables/secrets | Retain for redeployment |

These decisions define the destroy-plan and residual-cleanup contracts. They do not authorize destructive execution by themselves.

## 15. Closure Gate 1 conclusion

Closure Gate 1 is complete.

- all seven Terraform states are accounted for;
- Kubernetes, GitOps, operator, and controller-generated owners are known;
- every data-only resource has a cleanup and retention decision;
- legacy live-smoke SQS and Cognito resources are explicitly classified;
- bootstrap resources are separated from runtime resources;
- the GitHub OIDC provider ownership is resolved;
- no unexplained project resource remains in the read-only inventory.

The next permitted work is Closure Gate 3: create and review stage-specific destroy plans without applying them.