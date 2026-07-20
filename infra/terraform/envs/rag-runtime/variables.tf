variable "aws_region" { type = string }
variable "environment" { type = string }
variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "eks_cluster_primary_security_group_id" { type = string }
variable "backend_irsa_role_name" { type = string }
variable "backend_irsa_role_arn" { type = string }
variable "github_oidc_provider_arn" { type = string }
variable "github_repository" { type = string default = "siamese-lang/Terraformers-modernization" }
variable "corpus_ingestion_environment" { type = string default = "aws-rag-corpus-ingestion" }
variable "corpus_bucket_name" { type = string }
variable "corpus_prefix" { type = string default = "terraformers-reference/v1/" }
variable "tags" { type = map(string) default = {} }
