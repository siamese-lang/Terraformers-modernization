locals {
  common_name                   = "${var.name_prefix}-${var.environment}"
  backend_image_publish_subject = "repo:${var.github_repository}:environment:${var.backend_image_publish_environment}"
}

resource "aws_ecr_repository" "backend" {
  name                 = var.backend_ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the most recent backend images."
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_iam_role" "backend_image_publisher" {
  name = "${local.common_name}-backend-image-publisher"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.github_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = local.backend_image_publish_subject
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_policy" "backend_image_publisher" {
  name        = "${local.common_name}-backend-image-publisher"
  description = "Allows the dedicated GitHub OIDC publisher to push only the Terraformers backend image."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthorization"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "BackendRepositoryPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeImages",
        ]
        Resource = aws_ecr_repository.backend.arn
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backend_image_publisher" {
  role       = aws_iam_role.backend_image_publisher.name
  policy_arn = aws_iam_policy.backend_image_publisher.arn
}

resource "aws_s3_bucket" "uploads" {
  bucket = var.upload_bucket_name
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "results" {
  bucket = var.result_bucket_name
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_sqs_queue" "ai_log" {
  name                       = var.ai_log_queue_name
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 60
}

resource "aws_sqs_queue" "terraform_log" {
  name                       = var.terraform_log_queue_name
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 60
}

resource "aws_secretsmanager_secret" "backend_runtime" {
  name        = var.runtime_secret_name
  description = "Runtime secret container for the Terraformers backend. Values are written outside this public Terraform scaffold."
}
