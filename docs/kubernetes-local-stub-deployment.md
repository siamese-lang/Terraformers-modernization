# Kubernetes Local Stub Deployment

## 1. Purpose

This document defines the smallest Kubernetes deployment path for running the modernized Terraformers backend after the backend API contract baseline is complete.

The local-stub overlay is for proving that the backend container can start and serve the core API contract in a Kubernetes environment without requiring AWS resources, runtime secrets, RDS, Cognito, S3, SQS, Bedrock, or OpenSearch.

It is not a production deployment path.

## 2. Reuse / modify / exclude

```text
Reuse:
infra/kubernetes/base Deployment, Service, ServiceAccount, and ConfigMap shape
backend local profile
H2 in-memory database
stub/local adapter defaults

Modify:
Kustomize overlay sets SPRING_PROFILES_ACTIVE=local
Kustomize overlay removes runtime Secret dependency
Kustomize overlay uses terraformers-backend:local-stub with imagePullPolicy=Never

Exclude:
No AWS production resources
No RDS connection
No Cognito login restoration
No S3 writer/reader enablement
No SQS publisher enablement
No Bedrock/OpenSearch production validation
No Terraform run/apply/destroy feature
```

## 3. Overlay path

```text
infra/kubernetes/overlays/local-stub
```

The overlay renders the backend into this namespace:

```text
terraformers-local
```

It expects this image to already exist in the target cluster node runtime:

```text
terraformers-backend:local-stub
```

## 4. Build the backend image

From the repository root:

```bash
cd backend
mvn -q -DskipTests package
docker build -t terraformers-backend:local-stub .
cd ..
```

For kind:

```bash
kind load docker-image terraformers-backend:local-stub
```

For minikube, either build inside the minikube Docker daemon or load the image according to the local cluster runtime.

## 5. Render and apply

```bash
kubectl create namespace terraformers-local --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k infra/kubernetes/overlays/local-stub
kubectl -n terraformers-local rollout status deployment/terraformers-backend
```

## 6. Health check

```bash
kubectl -n terraformers-local port-forward svc/terraformers-backend 8080:80
```

In another terminal:

```bash
curl -fsS http://127.0.0.1:8080/actuator/health
```

Expected result:

```text
status: UP
```

## 7. API smoke path

The local profile uses H2 and disabled adapters, so the core API contract can be checked without AWS credentials.

Example upload:

```bash
printf 'fake image bytes' > /tmp/terraformers-architecture.png
curl -fsS -X POST \
  -F file=@/tmp/terraformers-architecture.png \
  http://127.0.0.1:8080/api/upload
```

Then check project tree and generated Terraform draft:

```bash
curl -fsS http://127.0.0.1:8080/api/project-tree/terraformers-architecture
curl -fsS http://127.0.0.1:8080/api/projects/terraformers-architecture/terraform/main.tf
```

## 8. Production transition boundary

After the local-stub path works, production-like deployment should be handled separately:

```text
1. provide immutable registry image tag
2. create environment-specific overlay
3. inject runtime secrets through External Secrets, Sealed Secrets, or CI/CD
4. add IRSA annotation to ServiceAccount in the environment overlay
5. enable one adapter at a time
6. validate the adapter with its own workflow or runbook
```

Do not turn on S3, SQS, Bedrock, OpenSearch, and Cognito in one PR. The current backend has adapter boundaries, but production evidence still has to be gathered per adapter.
