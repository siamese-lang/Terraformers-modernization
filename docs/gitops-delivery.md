# Backend immutable-digest GitOps delivery

This repository uses Git as the desired-state source for the Backend runtime and Argo CD as the reconciler. CloudFront remains the only public product entry; Argo CD is an internal operations component and its server is a `ClusterIP` Service with no Ingress, NLB, or ALB.

## Ownership boundaries

The GitOps application owns exactly the Backend runtime `ConfigMap`, `Deployment`, and `Service`. Bootstrap and infrastructure ownership remains separate: the namespace, Backend ServiceAccount and IRSA, runtime Secret or ExternalSecret, and private Backend Ingress are not part of GitOps. This avoids replacing the existing External Secrets integration or mixing infrastructure lifecycle with application releases.

The older Argo CD modules were consulted but intentionally not copied. They include patterns incompatible with this boundary: public ingress or NLB exposure, GitHub token/repository credential handling, mixed ownership of components, duplicate External Secrets management, and static-secret patterns. This implementation also does not install ingress-nginx or add an Argo CD Terraform root.

## Release flow

1. A Backend source change passes the existing scoped checks.
2. The existing GitHub OIDC workflow builds and pushes an immutable `git-<full-SHA>` ECR tag; it refuses to overwrite that tag.
3. The workflow resolves the actual ECR `sha256` digest.
4. When explicitly requested with `create_gitops_update_pr=true` (and `push_image=true`), it creates a branch and pull request that changes only `infra/kubernetes/gitops/backend-runtime/kustomization.yaml` to the resolved repository and digest.
5. After that PR is reviewed and merged, Argo CD reconciles the digest-based desired state.

The checked-in all-zero digest is source-safe only. It is never deployable: bootstrap must stop if the 64-zero placeholder has not been replaced by a real ECR digest. GitHub Actions does not use `kubectl`, Helm, or direct EKS mutation in this flow.

## Approved initial bootstrap

Initial Argo CD installation is an explicitly approved operator action, not a GitHub Actions workflow:

1. First create and merge a real digest-update PR; fail if the all-zero placeholder remains.
2. Add the official Argo Helm repository.
3. Run `helm upgrade --install` using chart `argo-cd` version **10.1.3** (which represents Argo CD **v3.4.5**) and `infra/kubernetes/argocd/values-dev.yaml`.
4. Wait for the Argo CD workloads to become ready.
5. Run `kubectl apply -f infra/kubernetes/argocd/backend-application.yaml` as the one-time bootstrap action.
6. Verify the Application is `Synced` and `Healthy`.
7. Verify the Git digest equals the Deployment image and the running Pod `imageID`.
8. Verify the CloudFront browser smoke path.

Operational access is local `kubectl port-forward` only; there is no public Argo CD endpoint and the initial admin password must not be exposed or printed.

## Rollback and self-heal

Rollback is a Git revert of the digest-update commit. Argo CD then restores the previous immutable digest. To demonstrate self-heal later, make one bounded, reversible, non-secret Deployment metadata drift and confirm Argo CD restores the committed value.

## Capacity and deferred work

This is a single-`t3.small`, non-HA development profile, not a production HA claim. If pods remain Pending or become memory-pressured, stop and use the separately approved Terraform node-scale path rather than repeatedly reducing requests. Monitoring, HPA, Backend replica changes, PDB, and recovery work are intentionally deferred to later PRs.
