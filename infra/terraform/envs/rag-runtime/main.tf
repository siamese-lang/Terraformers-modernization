locals {
  collection_name    = "${var.name_prefix}-${var.environment}-refs"
  encryption_name    = "${var.name_prefix}-${var.environment}-rag-enc"
  network_name       = "${var.name_prefix}-${var.environment}-rag-net"
  data_policy_name   = "${var.name_prefix}-${var.environment}-rag-data"
  vpc_endpoint_name  = "${var.name_prefix}-${var.environment}-rag-vpce"
  index_name         = "terraformers-reference-v1"
  vector_field       = "embedding"
  content_field      = "content"
  vector_dimension   = 1024
  embedding_model_id = "amazon.titan-embed-text-v2:0"
  common_tags = merge({
    Project     = "Terraformers"
    Environment = var.environment
    ManagedBy   = "terraform"
    Component   = "rag-runtime"
  }, var.tags)
}

resource "aws_security_group" "aoss_vpc_endpoint" {
  name        = local.vpc_endpoint_name
  description = "Only backend EKS traffic may reach the private AOSS endpoint."
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS from EKS cluster primary security group"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.eks_cluster_primary_security_group_id]
  }

  tags = merge(local.common_tags, { Name = local.vpc_endpoint_name })
}

resource "aws_opensearchserverless_vpc_endpoint" "collection" {
  name               = local.vpc_endpoint_name
  vpc_id             = var.vpc_id
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.aoss_vpc_endpoint.id]
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = local.encryption_name
  type = "encryption"
  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${local.collection_name}"]
    }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = local.network_name
  type = "network"
  policy = jsonencode([{
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${local.collection_name}"]
    }]
    AllowFromPublic = false
    SourceVPCEs     = [aws_opensearchserverless_vpc_endpoint.collection.id]
  }])
}

resource "aws_opensearchserverless_collection" "references" {
  name             = local.collection_name
  type             = "VECTORSEARCH"
  standby_replicas = "DISABLED"
  description      = "Private project-owned Terraform reference vector collection."
  tags             = local.common_tags

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]

  lifecycle {
    precondition {
      condition = alltrue([
        for name in [local.collection_name, local.encryption_name, local.network_name, local.data_policy_name, local.vpc_endpoint_name] :
        length(name) <= 32 && can(regex("^[a-z][a-z0-9-]*$", name))
      ])
      error_message = "All AOSS collection, policy, and VPC endpoint names must start with lowercase letters, use lowercase letters/numbers/hyphens only, and be 32 characters or fewer."
    }
  }
}

data "aws_iam_policy_document" "backend_aoss" {
  statement {
    sid       = "AossApiAccessToReferenceCollection"
    actions   = ["aoss:APIAccessAll"]
    resources = [aws_opensearchserverless_collection.references.arn]
  }
}

resource "aws_iam_policy" "backend_aoss" {
  name        = "${local.collection_name}-backend-aoss"
  description = "AOSS API identity access for the backend reference reader."
  policy      = data.aws_iam_policy_document.backend_aoss.json
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backend_aoss" {
  role       = var.backend_irsa_role_name
  policy_arn = aws_iam_policy.backend_aoss.arn
}

data "aws_iam_policy_document" "ingestion_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${var.corpus_ingestion_environment}"]
    }
  }
}

resource "aws_iam_role" "corpus_ingestion" {
  name               = "${local.collection_name}-corpus-ingestion"
  assume_role_policy = data.aws_iam_policy_document.ingestion_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "corpus_ingestion" {
  statement {
    sid       = "CorpusObjectsOnly"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.corpus.arn}/${var.corpus_prefix}*"]
  }

  statement {
    sid       = "ListCorpusPrefix"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.corpus.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.corpus_prefix}*"]
    }
  }

  statement {
    sid       = "AossApiAccessToReferenceCollection"
    actions   = ["aoss:APIAccessAll"]
    resources = [aws_opensearchserverless_collection.references.arn]
  }

  statement {
    sid       = "EmbedCorpusDocuments"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:aws:bedrock:${var.aws_region}::foundation-model/${local.embedding_model_id}"]
  }
}

resource "aws_iam_policy" "corpus_ingestion" {
  name        = "${local.collection_name}-corpus-ingestion"
  description = "Scoped corpus ingestion identity policy."
  policy      = data.aws_iam_policy_document.corpus_ingestion.json
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "corpus_ingestion" {
  role       = aws_iam_role.corpus_ingestion.name
  policy_arn = aws_iam_policy.corpus_ingestion.arn
}

resource "aws_opensearchserverless_access_policy" "data" {
  name = local.data_policy_name
  type = "data"
  policy = jsonencode([
    {
      Description = "Read-only backend access to one Terraformers reference index"
      Principal   = [var.backend_irsa_role_arn]
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
          Permission   = ["aoss:DescribeCollectionItems"]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${local.collection_name}/${local.index_name}"]
          Permission   = ["aoss:DescribeIndex", "aoss:ReadDocument"]
        },
      ]
    },
    {
      Description = "Scoped corpus ingestion access to one Terraformers reference index"
      Principal   = [aws_iam_role.corpus_ingestion.arn]
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/${local.collection_name}"]
          Permission   = ["aoss:DescribeCollectionItems"]
        },
        {
          ResourceType = "index"
          Resource     = ["index/${local.collection_name}/${local.index_name}"]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DescribeIndex",
            "aoss:UpdateIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument",
          ]
        },
      ]
    },
  ])
}

resource "aws_s3_bucket" "corpus" {
  bucket        = var.corpus_bucket_name
  force_destroy = false
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "corpus" {
  bucket                  = aws_s3_bucket.corpus.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "corpus" {
  bucket = aws_s3_bucket.corpus.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "corpus" {
  bucket = aws_s3_bucket.corpus.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "corpus" {
  bucket = aws_s3_bucket.corpus.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
