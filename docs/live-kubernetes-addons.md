# Live Kubernetes Add-ons

## Version contract

Source of truth:

```text
config/live-kubernetes-addons.json
```

Pinned pair:

```text
EKS Kubernetes                     1.35
AWS Load Balancer Controller      3.4.2
External Secrets Operator chart   2.7.0
```

No chart installation or Kubernetes mutation has been performed.

## Single-node resource baseline

The current baseline is one `t3.small` worker. This is a validation baseline,
not a production sizing decision. The repository values files pin the rendered
requests and limits before a future install:

```text
AWS Load Balancer Controller values
infra/kubernetes/aws-runtime-origin/aws-load-balancer-controller-values.yaml
  request: 100m CPU / 128Mi memory
  limit:   500m CPU / 256Mi memory

External Secrets values
infra/kubernetes/external-secrets/external-secrets-values.yaml
  controller, webhook, cert-controller (one replica each)
  per Deployment request: 10m CPU / 32Mi memory
  per Deployment limit:   100m CPU / 128Mi memory
```

Together the add-ons request 130m CPU, 224Mi memory, and four Pods. With the
current system baseline and one backend replica, the expected remaining
allocatable capacity is about 1200m CPU, 556.2Mi memory, and two Pod slots.
During a backend rolling update, the memory headroom is about 44.2Mi and needs
a separate production-sizing decision before production use.

## AWS Load Balancer Controller

```text
repository: https://aws.github.io/eks-charts
chart:      eks/aws-load-balancer-controller
version:    3.4.2
namespace:  kube-system
ServiceAccount: aws-load-balancer-controller
```

The ServiceAccount is created from the reviewed deployment package with the Terraform IRSA role annotation. Helm must use:

```text
serviceAccount.create=false
serviceAccount.name=aws-load-balancer-controller
```

The controller IAM policy is pinned with the same version:

```text
infra/terraform/envs/eks-runtime/policies/aws-load-balancer-controller-v3.4.2.json
```

Approved future install shape:

```powershell
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller `
  eks/aws-load-balancer-controller `
  --version 3.4.2 `
  --namespace kube-system `
  --values infra\kubernetes\aws-runtime-origin\aws-load-balancer-controller-values.yaml `
  --wait `
  --timeout 10m
```

This command is documentation only until explicit approval. For a new install, the Helm chart manages its CRDs. For a future chart upgrade, review and update CRDs separately because Helm upgrade does not automatically upgrade them.

## External Secrets Operator

```text
repository: https://charts.external-secrets.io
chart:      external-secrets/external-secrets
version:    2.7.0
namespace:  external-secrets
controller ServiceAccount: external-secrets
provider-auth ServiceAccount: terraformers-runtime/terraformers-external-secrets
```

The controller ServiceAccount and provider-auth ServiceAccount must remain separate.

- `external-secrets` runs the controller and does not receive the Terraformers Secrets Manager IRSA role.
- `terraformers-external-secrets` is created by the generated runtime package and is referenced by the namespaced SecretStore JWT auth.

Pinned CRD source:

```text
https://raw.githubusercontent.com/external-secrets/external-secrets/v2.7.0/deploy/crds/bundle.yaml
```

Approved future install shape:

```powershell
$CrdPath = "artifacts\external-secrets-v2.7.0-crds.yaml"

Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/external-secrets/external-secrets/v2.7.0/deploy/crds/bundle.yaml" `
  -OutFile $CrdPath

kubectl apply `
  --server-side `
  --filename $CrdPath

helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets `
  external-secrets/external-secrets `
  --version 2.7.0 `
  --namespace external-secrets `
  --create-namespace `
  --values infra\kubernetes\external-secrets\external-secrets-values.yaml `
  --wait `
  --timeout 10m
```

These commands are documentation only until explicit approval.

## Pre-apply verification

Before any install:

```text
1. Use a compatible `kubectl` 1.35.x client and a kubeconfig that points to the expected account and cluster.
2. kubectl auth can-i output is reviewed.
3. controller/provider ServiceAccount identity is not shared.
4. chart versions match config/live-kubernetes-addons.json.
5. AWS Load Balancer Controller policy checksum matches CI evidence.
6. External Secrets CRDs use external-secrets.io/v1.
7. no chart command uses an unversioned chart.
8. no static AWS access key is passed through Helm values.
```

## Post-install evidence

```powershell
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get deployment -n external-secrets
kubectl get crd secretstores.external-secrets.io externalsecrets.external-secrets.io
kubectl get serviceaccount -n kube-system aws-load-balancer-controller -o yaml
kubectl get serviceaccount -n terraformers-runtime terraformers-external-secrets -o yaml
```

Do not print Kubernetes Secret data during validation.
