# AWS Environment Contract

## Purpose

This document is the canonical static contract between the current Spring Boot production profile, the public-safe Kubernetes package, the React production build, Terraform outputs, deployment scripts, and GitHub Actions configuration references.

It does not claim that a real AWS account, Terraform state, GitHub Environment, EKS cluster, IRSA role, or Secret provider is configured. A repository reference or Terraform declaration proves only that the contract exists in source; live values and permissions remain deployment preconditions.

## Safety boundary

The static contract gates perform no AWS authentication and no infrastructure or cluster mutation.

They do not run:

- `terraform plan`, `apply`, or `destroy`
- `kubectl apply`
- Docker image push
- External Secrets installation
- Bedrock, OpenSearch, SQS, or S3 production-adapter enablement

## Canonical backend base contract

The production backend must receive these eight keys through `terraformers-backend-runtime-secrets`:

| Kubernetes Secret key | Spring consumer | Discovered Terraform source | Remaining mapping work |
|---|---|---|---|
| `SPRING_DATASOURCE_URL` | `spring.datasource.url` | `spring_datasource_url` | Terraform output to runtime Secret key |
| `SPRING_DATASOURCE_USERNAME` | `spring.datasource.username` | `database_username` | Terraform output or managed secret to runtime Secret key |
| `SPRING_DATASOURCE_PASSWORD` | `spring.datasource.password` | `database_master_user_secret_arn` | managed-secret JSON field to runtime Secret key |
| `COGNITO_REGION` | Cognito issuer construction | `cognito_region` | Terraform output to runtime Secret key and frontend variable |
| `COGNITO_USER_POOL_ID` | Cognito issuer construction | `cognito_user_pool_id` | Terraform output to runtime Secret key and frontend variable |
| `COGNITO_USER_POOL_CLIENT_ID` | JWT client validation | `cognito_user_pool_client_id` | Terraform output to runtime Secret key and frontend variable |
| `COGNITO_JWKS_URL` | JWT JWK set URI | `cognito_jwks_url` | Terraform output to runtime Secret key |
| `S3_BUCKET_NAME` | upload/source object storage and default result bucket | `upload_bucket_name` | Terraform output to runtime Secret key and workload IAM verification |

`ANALYSIS_RESULT_BUCKET_NAME` is an optional override. The repository also declares `result_bucket_name`; when the override is omitted, the backend uses `S3_BUCKET_NAME` as its result bucket.

The following former documentation aliases are not part of the canonical backend runtime contract:

- `AWS_S3_BUCKET_NAME`
- `FRONTEND_URL`
- `DOMAIN`

A deployment script may still use a generic domain input for DNS or frontend infrastructure, but it must never inject that name as a backend Secret key.

## Discovered infrastructure outputs

The repository inventory currently matches these source contracts:

| Area | Terraform output |
|---|---|
| backend image repository | `backend_image_repository_url` |
| upload bucket | `upload_bucket_name` |
| result bucket | `result_bucket_name` |
| runtime Secret ARN | `backend_runtime_secret_arn` |
| Kubernetes runtime Secret name | `kubernetes_runtime_secret_name` |
| RDS endpoint / port / database | `database_endpoint`, `database_port`, `database_name` |
| RDS username / managed credential | `database_username`, `database_master_user_secret_arn` |
| complete JDBC URL | `spring_datasource_url` |
| Cognito | `cognito_region`, `cognito_user_pool_id`, `cognito_user_pool_client_id`, `cognito_jwks_url` |
| EKS cluster | `cluster_name` |
| backend namespace / ServiceAccount | `backend_namespace`, `backend_service_account_name` |
| backend IRSA role | `backend_irsa_role_arn` |

The following delivery outputs are still absent and remain explicit preflight gaps:

- frontend hosting bucket output
- CloudFront distribution output

## GitHub Actions AWS authentication contract

AWS-capable workflows use GitHub OIDC only.

Canonical references are:

- repository/environment Variable: `AWS_REGION`
- repository/environment Secret: `AWS_ROLE_TO_ASSUME`

A manual workflow input may override either value for an explicitly selected environment, but there is no fallback to `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`. Build-only image verification does not configure AWS credentials.

The inventory verifies source references only. It does not prove that `AWS_REGION`, `AWS_ROLE_TO_ASSUME`, the IAM trust policy, or the role permissions are configured in GitHub or AWS.

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

Terraform declares the intended namespace, ServiceAccount, IRSA role, runtime Secret ARN, and Kubernetes Secret name. The environment-specific manifest renderer and Secret delivery mechanism must still prove that these exact values are propagated together.

## Frontend build contract

The browser build may receive only these public build-time values:

| Build variable | Intended source |
|---|---|
| `REACT_APP_API_BASE_URL` | deployed backend origin; unresolved until frontend/backend routing is defined |
| `REACT_APP_AWS_REGION` | `cognito_region` |
| `REACT_APP_COGNITO_USER_POOL_ID` | `cognito_user_pool_id` |
| `REACT_APP_COGNITO_USER_POOL_CLIENT_ID` | `cognito_user_pool_client_id` |

Database credentials, bucket object identifiers, queue URLs, model IDs, OpenSearch settings, and server-side Secret keys must never be added to the frontend environment contract.

Frontend hosting remains incomplete at the Terraform-output layer because no frontend bucket or CloudFront distribution output is currently matched.

## Static verification

Run:

```bash
bash scripts/checks/aws-environment-contract-verification.sh
python3 scripts/checks/aws-deployment-contract-inventory.py
```

The first checker compares:

1. `application-prod.yml` required keys
2. active and documented keys in `backend-secret.example.yaml`
3. disabled adapter switches in `backend-configmap.yaml`
4. optional adapter requirements in `RuntimeAdapterContractValidator`
5. React `.env.example` build variables
6. rendered AWS runtime-template identities, image policy, and Secret reference

The repository inventory then collects:

1. every Terraform `output` and `variable` declaration in the checkout
2. every GitHub Actions `${{ vars.* }}` and `${{ secrets.* }}` reference
3. deployment-script environment-variable references
4. the production `required-env` contract and Spring placeholders
5. Kubernetes runtime keys
6. frontend public build variables

It fails immediately when:

- no Terraform output contract exists
- a workflow references `secrets.AWS_ACCESS_KEY_ID` or `secrets.AWS_SECRET_ACCESS_KEY`
- a legacy backend runtime key is active in Spring or Kubernetes configuration
- the exact production `required-env` order or frontend public contract drifts

Output-name groups that cannot yet be matched are warnings and remain explicit in the evidence rather than being guessed.

Evidence is written to `artifacts/aws-environment-contract` and uploaded as `aws-environment-contract-evidence` on every combined workflow run.

## Remaining AWS preflight work

1. Validate that GitHub repository/environment values `AWS_REGION` and `AWS_ROLE_TO_ASSUME` exist.
2. Validate the IAM OIDC trust policy and least-privilege policies for image publishing and validation workflows.
3. Define the exact managed-secret JSON field mapping for datasource username and password.
4. Prove Terraform output propagation into the environment-specific Kubernetes Secret and IRSA annotation.
5. Reconcile ECR immutable image URI propagation into the environment overlay.
6. Verify RDS TLS settings and the EKS-to-RDS security-group path.
7. Verify S3 bucket IAM permissions before enabling reader or writer adapters.
8. Add or explicitly exclude frontend S3/CloudFront infrastructure and outputs.
9. Define `REACT_APP_API_BASE_URL` from the chosen backend routing model without adding public ingress implicitly.

No live AWS deployment should start until those mappings are explicit and both static gates remain green.
