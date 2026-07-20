# Phase 3 RAG runtime foundation

PR #55 completed Phase 2's Spring Boot retrieval lifecycle: architecture image to Bedrock architecture facts, embedding, signed `aoss` k-NN retrieval, retrieved references, then Bedrock Terraform generation. This Phase 3 PR adds only the reviewable infrastructure and corpus contracts; it does not apply AWS resources, create an index, upload corpus objects, embed documents, or query a live collection.

## Infrastructure contract

`infra/terraform/envs/rag-runtime` deliberately uses the classic OpenSearch Serverless `VECTORSEARCH` collection supported by the pinned `hashicorp/aws` **5.100.0** provider. NextGen collection groups and provider 6.x are separate major-version decisions. The collection uses AWS-owned encryption, explicit tags, and `standby_replicas = "DISABLED"` to establish the smallest intended cost baseline.

The collection data plane is private: its network policy allows only its created VPC endpoint, with no public access, Dashboards rule, or Bedrock Knowledge Bases service exception. That endpoint has a dedicated security group admitting TCP/443 only from the EKS managed cluster primary security group. CloudFront remains the sole public product entry; the backend and vector store remain private workloads.

The existing backend IRSA role receives a separate identity policy limited to `aoss:APIAccessAll` on this collection and an AOSS data policy limited to describe/index-read/document-read. A separate GitHub Environment OIDC ingestion role has exact `sts.amazonaws.com` and environment subject trust, plus narrowly scoped corpus-prefix S3, embedding invoke, and write-index permissions. Neither role administers AOSS policies; the backend cannot write or delete documents or create indexes.

The dedicated corpus bucket has public access blocks, versioning, AES256 server-side encryption, BucketOwnerEnforced ownership, and `force_destroy = false`. Its name is supplied as a variable and it is never a destination for Terraform state, uploads, generated Terraform, or secrets.

## Corpus and index contract

The project-owned source lives in `corpus/terraformers-reference/v1`. It contains normalized guidance rather than PDFs or copied provider pages. The fixed contract is Titan Text Embeddings v2 (`amazon.titan-embed-text-v2:0`), dimension 1024, signing service `aoss`, top-K 3, index `terraformers-reference-v1`, vector field `embedding`, and content field `content`. The schema uses Faiss HNSW cosine k-NN and filterable metadata. The offline standard-library validator calculates a deterministic SHA-256 summary without AWS access or embedding creation.

## Apply and operations boundary

Before any apply, review the plan and generate the lock file through Terraform CLI or GitHub Actions; no lock-file checksum is hand-authored here. After an approved apply, perform a short, controlled verification period, then make and document a retention or cleanup decision. Do not repeatedly destroy and recreate the collection. Fix only the first failing boundary before proceeding to the next verification step.

Index creation, corpus upload/ingestion, Bedrock embeddings, live signed k-NN validation, backend rollout, REQUIRED-mode failure validation, and browser RAG E2E remain later work. The frontend browser smoke is also still a prerequisite for a live Phase 3 apply until recorded.

Expected cost exposure begins only after apply: AOSS collection capacity and endpoint/network charges, S3 object/version storage, and Bedrock embedding calls during the later ingestion phase. Disabled standby replicas does not eliminate these costs.
