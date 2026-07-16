# AWS Environment Contract

## Purpose

This document is the canonical static contract between the current Spring Boot production profile, the public-safe Kubernetes package, the React production build, Terraform outputs, deployment scripts, and GitHub Actions configuration references.

It does not claim that a real AWS account, Terraform state, GitHub Environment, EKS cluster, IRSA role, or Secret provider is configured. Those mappings remain deployment preconditions and must be verified separately before any live apply or rollout.

## Safety boundary

The static contract gates perform no AWS authentication and no infrastructure or cluster mutation. They do not run Terraform plan/apply/destroy, Docker image push, Kubernetes apply, External Secrets installation, or production adapter enablement.

## Canonical backend base contract

The production backend requires these eight keys through `terraformers-backend-runtime-secrets`:

| Kubernetes Secret key | Terraform/source contract |
|---|---|
| `SPRING_DATASOURCE_URL` | `spring_datasource_url` |
| `SPRING_DATASOURCE_USERNAME` | `database_username` |
| `SPRING_DATASOURCE_PASSWORD` | private delivery from the RDS-managed credential path |
| `COGNITO_REGION` | `cognito_region` |
| `COGNITO_USER_POOL_ID` | `cognito_user_pool_id` |
| `COGNITO_USER_POOL_CLIENT_ID` | `cognito_user_pool_client_id` |
| `COGNITO_JWKS_URL` | `cognito_jwks_url` |
| `S3_BUCKET_NAME` | `upload_bucket_name` |

`ANALYSIS_RESULT_BUCKET_NAME` is an optional override sourced from `result_bucket_name`. When absent, the backend uses `S3_BUCKET_NAME` as the result bucket.

The following former aliases are not part of the backend runtime contract:

- `AWS_S3_BUCKET_NAME`
- `FRONTEND_URL`
- `DOMAIN`

A deployment script may use a generic domain input for DNS or frontend infrastructure, but it must never inject that name as a backend Secret key.

## Optional adapter contract

Adapters remain disabled in the base ConfigMap and AWS runtime template. Enabling a switch requires its corresponding resource, network path, IAM policy, and runtime setting to be verified together.

| ConfigMap switch | Required setting keys |
|---|---|
| `BEDROCK_PROVIDER_ENABLED=true` | `BEDROCK_MODEL_ID` |
| `BEDROCK_EMBEDDING_ENABLED=true` | `BEDROCK_EMBEDDING_MODEL_ID` |
| `OPENSEARCH_RETRIEVER_ENABLED=true` | `OPENSEARCH_ENDPOINT`, `INDEX_NAME`, `VECTOR_FIELD_NAME`, `CONTENT_FIELD_NAME` |
| `ANALYSIS_SQS_PUBLISHER_ENABLED=true` | `AI_LOG_QUEUE_URL`, `TERRAFORM_LOG_QUEUE_URL` |
| `S3_READER_ENABLED=true` | base bucket configuration plus workload IAM permission |
| `S3_WRITER_ENABLED=true` | base/result bucket configuration plus workload IAM permission |

Optional adapter settings are not included in the base runtime input bundle and placeholder values are rejected.

## Terraform-to-deployment source contract

The current Terraform environments expose the following source values:

| Delivery concern | Terraform output |
|---|---|
| backend image repository | `backend_image_repository_url` |
| upload bucket | `upload_bucket_name` |
| result bucket | `result_bucket_name` |
| runtime Secret container | `backend_runtime_secret_arn` |
| Kubernetes Secret name | `kubernetes_runtime_secret_name` |
| JDBC URL | `spring_datasource_url` |
| database username | `database_username` |
| RDS-managed credential pointer | `database_master_user_secret_arn` |
| Cognito region | `cognito_region` |
| Cognito user pool | `cognito_user_pool_id` |
| Cognito app client | `cognito_user_pool_client_id` |
| Cognito JWKS URL | `cognito_jwks_url` |
| EKS cluster | `cluster_name` |
| backend namespace | `backend_namespace` |
| backend ServiceAccount | `backend_service_account_name` |
| backend IRSA role | `backend_irsa_role_arn` |

`build-aws-runtime-input-bundle.py` validates that:

- the image URI belongs to `backend_image_repository_url`
- the image uses an immutable tag or SHA-256 digest and never `latest`
- namespace, ServiceAccount, and Kubernetes Secret names match the canonical runtime identities
- the generated base Secret env contains exactly the eight required keys plus the optional result bucket override
- disabled adapter settings are absent
- the source map contains pointers and status only, never the database password

The database password and the final provider-to-Kubernetes Secret synchronization remain private deployment inputs. Their existence is not inferred from the Terraform output declarations.

## GitHub Actions credential contract

AWS-capable workflows use GitHub OIDC only:

- repository/environment variable: `AWS_REGION`
- repository/environment secret: `AWS_ROLE_TO_ASSUME`

Manual workflow inputs may override those values, but `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` repository secrets are forbidden.

The workflow reference reconciliation step scans complete `${{ ... }}` expressions, including references that appear after `inputs.* ||`, and patches the generated inventory evidence with the actual counts and locations.

## Kubernetes runtime contract

The public-safe AWS template and input bundle use these identities:

| Item | Contract |
|---|---|
| namespace | `terraformers-runtime` |
| ServiceAccount | `terraformers-backend` |
| ConfigMap | `terraformers-backend-runtime-config` |
| Secret reference | `terraformers-backend-runtime-secrets` |
| Deployment | `terraformers-backend` |
| Service | `terraformers-backend` |
| Spring profile | `prod` |
| image | explicit immutable ECR value; never `latest` |

The public template deliberately contains no real account/registry value, committed Secret resource, live Secret provider, or public ingress.

## Frontend build contract

The browser build may receive only these public values:

- `REACT_APP_API_BASE_URL`
- `REACT_APP_AWS_REGION`
- `REACT_APP_COGNITO_USER_POOL_ID`
- `REACT_APP_COGNITO_USER_POOL_CLIENT_ID`

Database credentials, queue URLs, model IDs, OpenSearch settings, and server-side Secret keys must never enter the frontend contract.

## Static verification

The combined workflow runs:

```bash
bash scripts/checks/aws-environment-contract-verification.sh
python3 scripts/checks/aws-deployment-contract-inventory.py
python3 scripts/checks/aws-workflow-reference-reconciliation.py
bash scripts/checks/aws-runtime-input-bundle-contract-verification.sh
```

Evidence is uploaded from:

- `artifacts/aws-environment-contract`
- `artifacts/aws-runtime-input-bundle-contract`

Local and downloaded evidence is ignored by Git through the root `artifacts/` rule.

## Remaining AWS preflight work

Before live deployment, the following still require explicit verification:

1. GitHub OIDC provider trust and `AWS_ROLE_TO_ASSUME` permissions
2. RDS-managed credential to backend runtime Secret field mapping
3. runtime Secret delivery mechanism and rotation behavior
4. RDS security-group path and TLS behavior from EKS workloads
5. published ECR image digest/tag propagation into the rendered manifest
6. actual IRSA trust subject for namespace and ServiceAccount
7. S3 workload permissions for the disabled reader/writer adapters before activation
8. frontend hosting bucket and CloudFront distribution, which currently have no Terraform output contract
9. frontend API origin and browser authentication routing

No live AWS deployment should start until these mappings are explicit and all static gates remain green.
