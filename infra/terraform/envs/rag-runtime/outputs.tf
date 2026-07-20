output "collection_id" {
  value = aws_opensearchserverless_collection.references.id
}
output "collection_arn" {
  value = aws_opensearchserverless_collection.references.arn
}
output "collection_endpoint" {
  value = aws_opensearchserverless_collection.references.collection_endpoint
}
output "vpc_endpoint_id" {
  value = aws_opensearchserverless_vpc_endpoint.collection.id
}
output "index_name" {
  value = local.index_name
}
output "vector_field" {
  value = local.vector_field
}
output "content_field" {
  value = local.content_field
}
output "vector_dimension" {
  value = local.vector_dimension
}
output "embedding_model_id" {
  value = local.embedding_model_id
}
output "opensearch_signing_service" {
  value = "aoss"
}
output "top_k_default" {
  value = 3
}
output "corpus_bucket_name" {
  value = aws_s3_bucket.corpus.bucket
}
output "corpus_prefix" {
  value = var.corpus_prefix
}
output "ingestion_role_arn" {
  value = aws_iam_role.corpus_ingestion.arn
}
output "backend_runtime_iam_policy_arn" {
  value = aws_iam_policy.backend_rag_runtime.arn
}
output "codebuild_ingestion_project_name" { value = aws_codebuild_project.corpus_ingestion.name }
output "codebuild_ingestion_project_arn" { value = aws_codebuild_project.corpus_ingestion.arn }
output "codebuild_ingestion_role_arn" { value = aws_iam_role.codebuild_ingestion.arn }
output "codebuild_ingestion_security_group_id" { value = aws_security_group.codebuild_ingestion.id }
