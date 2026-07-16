# AWS Environment Contract

## Purpose

This document is the canonical static contract between the current Spring Boot production profile, the public-safe Kubernetes package, and the React production build.

It does not claim that a real AWS account, Terraform state, GitHub Environment, EKS cluster, IRSA role, or Secret provider is configured. Those mappings remain deployment preconditions and must be verified separately before any live apply or rollout.

## Safety boundary

The static contract gate performs no AWS authentication and no infrastructure or cluster mutation.

It does not run:

- `terraform plan`, `apply`, or `destroy`
- `kubectl apply`
- Docker image push
- External Secrets installation
- Bedrock, OpenSearch, SQS, or S3 production-adapter enablement

## Canonical backend base contract

The production backend must receive these eight keys through `terraformers-backend-runtime-secrets`:

| Kubernetes Secret key | Spring consumer | Intended AWS source | Current mapping status |
|---|---|---|---|
| `SPRING_DATASOURCE_URL` | `spring.datasource.url` | RDS endpoint, port, database name, and JDBC options | Terraform output/GitHub mapping unresolved |
| `SPRING_DATASOURCE_USERNAME` | `spring.datasource.username` | managed database credential | Secret provider mapping unresolved |
| `SPRING_DATASOURCE_PASSWORD` | `spring.datasource.password` | managed database credential | Secret provider mapping unresolved |
| `COGNITO_REGION` | Cognito issuer construction | Cognito/Terraform region | Terraform output/GitHub mapping unresolved |
| `COGNITO_USER_POOL_ID` | Cognito issuer construction | Cognito user-pool output | Terraform output/GitHub mapping unresolved |
| `COGNITO_USER_POOL_CLIENT_ID` | JWT client validation | Cognito app-client output | Terraform output/GitHub mapping unresolved |
| `COGNITO_JWKS_URL` | JWT JWK set URI | derived from region and user-pool ID or explicit output | Terraform output/GitHub mapping unresolved |
| `S3_BUCKET_NAME` | upload/source object storage and default result bucket | application bucket output | Terraform output/GitHub mapping unresolved |

`ANALYSIS_RESULT_BUCKET_NAME` is an optional override. When absent, the backend uses `S3_BUCKET_NAME` as the result bucket.

The following former documentation aliases are not part of the canonical backend contract:

- `AWS_S3_BUCKET_NAME`
- `FRONTEND_URL`
- `DOMAIN`

## Optional adapter contract

Adapters remain disabled in the base and AWS template ConfigMaps. Enabling a switch requires the corresponding settings before the pod starts.

| ConfigMap switch | Required setting keys |
|---|---|
| `BEDROCK_PROVIDER_ENABLED=true` | `BEDROCK_MODEL_ID` |
| `BEDROCK_EMBEDDING_ENABLED=true` | `BEDROCK_EMBEDDING_MODEL_ID` |
| `OPENSEARCH_RETRIEVER_ENABLED=true` | `OPENSEARCH_ENDPOINT`, `INDEX_NAME`, `VECTOR_FIELD_NAME`, `CONTENT_FIELD_NAME` |
| `ANALYSIS_SQS_PUBLISHER_ENABLED=true` | `AI_LOG_QUEUE_URL`, `TERRAFORM_LOG_QUEUE_URL` |
| `S3_READER_ENABLED=true` | base `S3_BUCKET_NAME` plus workload IAM permission |
| `S3_WRITER_ENABLED=true` | base/result bucket configuration plus workload IAM permission |

An environment-specific overlay must not enable any adapter until its AWS resource, network path, IAM policy, and runtime settings have been verified together.

## Kubernetes runtime contract

The public-safe AWS template renders these fixed identities:

| Item | Contract |
|---|---|
| namespace | `terraformers-runtime` |
| ServiceAccount | `terraformers-backend` |
| ConfigMap | `terraformers-backend-runtime-config` |
| Secret reference | `terraformers-backend-runtime-secrets` |
| Deployment | `terraformers-backend` |
| Service | `terraformers-backend` |
| Spring profile | `prod` |
| image | explicit immutable replacement value; never `latest` |

The template deliberately does not contain:

- a committed Secret resource
- a real ECR registry/account value
- a ServiceAccount IRSA annotation
- a live Secret provider resource
- public ingress or ALB exposure

These are unresolved environment-specific deployment inputs, not implicit defaults.

## Frontend build contract

The browser build may receive only these public build-time values:

| Build variable | Purpose |
|---|---|
| `REACT_APP_API_BASE_URL` | deployed backend API origin |
| `REACT_APP_AWS_REGION` | Cognito client region |
| `REACT_APP_COGNITO_USER_POOL_ID` | browser authentication user pool |
| `REACT_APP_COGNITO_USER_POOL_CLIENT_ID` | browser authentication app client |

Database credentials, bucket object identifiers, queue URLs, model IDs, OpenSearch settings, and server-side Secret keys must never be added to the frontend environment contract.

## Static verification

Run:

```bash
bash scripts/checks/aws-environment-contract-verification.sh
```

The checker compares:

1. `application-prod.yml` required keys
2. the active and documented keys in `backend-secret.example.yaml`
3. disabled adapter switches in `backend-configmap.yaml`
4. optional adapter requirements in `RuntimeAdapterContractValidator`
5. the React `.env.example` build variables
6. the rendered AWS runtime-template identities, image policy, and Secret reference

Evidence is written to `artifacts/aws-environment-contract`.

## Remaining AWS preflight work

The next gate must inspect and reconcile the real infrastructure and automation layers:

1. Terraform output names and actual module/resource ownership
2. GitHub repository/environment Variables and Secrets referenced by workflows
3. ECR repository names and immutable image propagation
4. EKS namespace and ServiceAccount IRSA annotations
5. RDS endpoint, database name, credentials, TLS, and security-group path
6. Cognito region, user pool, app client, issuer, and JWK URL
7. S3 bucket names and workload IAM permissions
8. Secret delivery mechanism and exact provider-to-Kubernetes key mapping
9. frontend build variables and CloudFront/backend origin routing

No live AWS deployment should start until those mappings are explicit and the static checker remains green.
