data "aws_caller_identity" "current" {}

locals {
  normalized_state_prefix = trim(var.state_prefix, "/")
  create_oidc_provider    = var.existing_github_oidc_provider_arn == null
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name
  tags   = var.common_tags

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.expected_aws_account_id
      error_message = "The authenticated AWS account does not match expected_aws_account_id."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.state_bucket.json
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = local.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = var.common_tags
}

locals {
  github_oidc_provider_arn     = local.create_oidc_provider ? aws_iam_openid_connect_provider.github_actions[0].arn : var.existing_github_oidc_provider_arn
  terraform_apply_oidc_subject = "repo:${var.github_repository}:environment:${var.apply_github_environment}"
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    sid     = "GitHubEnvironmentOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.github_oidc_subjects
    }
  }
}

resource "aws_iam_role" "terraform_plan" {
  name                 = var.plan_role_name
  assume_role_policy   = data.aws_iam_policy_document.github_actions_assume_role.json
  max_session_duration = 3600
  tags                 = var.common_tags

  lifecycle {
    precondition {
      condition = (
        var.existing_github_oidc_provider_arn == null ||
        try(split(":", var.existing_github_oidc_provider_arn)[4], "") == var.expected_aws_account_id
      )
      error_message = "existing_github_oidc_provider_arn must belong to expected_aws_account_id."
    }
  }
}

resource "aws_iam_role_policy_attachment" "terraform_plan_read_only" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "terraform_state_access" {
  statement {
    sid     = "ListStatePrefix"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.terraform_state.arn,
    ]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        local.normalized_state_prefix,
        "${local.normalized_state_prefix}/*",
      ]
    }
  }

  statement {
    sid    = "ReadWriteStateAndLockFiles"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      "${aws_s3_bucket.terraform_state.arn}/${local.normalized_state_prefix}/*/terraform.tfstate",
    ]
  }

  statement {
    sid    = "ManageNativeLockFiles"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.terraform_state.arn}/${local.normalized_state_prefix}/*/terraform.tfstate.tflock",
    ]
  }
}

resource "aws_iam_role_policy" "terraform_state_access" {
  name   = "terraformers-live-state-access"
  role   = aws_iam_role.terraform_plan.id
  policy = data.aws_iam_policy_document.terraform_state_access.json
}

data "aws_iam_policy_document" "github_actions_apply_assume_role" {
  statement {
    sid     = "GitHubApplyEnvironmentOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.terraform_apply_oidc_subject]
    }
  }
}

resource "aws_iam_role" "terraform_apply" {
  name                 = var.apply_role_name
  assume_role_policy   = data.aws_iam_policy_document.github_actions_apply_assume_role.json
  max_session_duration = 3600
  tags                 = var.common_tags

  lifecycle {
    precondition {
      condition     = try(split(":", var.approved_apply_iam_policy_arn)[4], "") == var.expected_aws_account_id
      error_message = "approved_apply_iam_policy_arn must belong to expected_aws_account_id."
    }
  }
}

resource "aws_iam_role_policy_attachment" "terraform_apply_read_only" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "terraform_apply_state_access" {
  name   = "terraformers-live-apply-state-access"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_state_access.json
}

data "aws_iam_policy_document" "terraform_apply_iam_mutation" {
  statement {
    sid    = "UpdateApprovedBackendRuntimeAccessPolicy"
    effect = "Allow"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:DeletePolicyVersion",
    ]
    resources = [var.approved_apply_iam_policy_arn]
  }
}

resource "aws_iam_role_policy" "terraform_apply_iam_mutation" {
  name   = "terraformers-live-apply-approved-policy-mutation"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply_iam_mutation.json
}

data "aws_iam_policy_document" "terraform_apply_rag_runtime_create" {
  statement {
    sid    = "CreateAndConfigureExactCorpusBucket"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketEncryption",
      "s3:PutBucketVersioning",
      "s3:PutBucketTagging",
    ]
    resources = ["arn:aws:s3:::${var.rag_runtime_corpus_bucket_name}"]
  }

  statement {
    sid    = "CreateExactRagIamRolesAndPolicies"
    effect = "Allow"
    actions = ["iam:CreateRole", "iam:TagRole"]
    resources = [
      "arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-corpus-ingestion",
      "arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-codebuild",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["terraformers-modernization"]
    }
  }

  statement {
    sid     = "CreateExactRagIamPolicies"
    effect  = "Allow"
    actions = ["iam:CreatePolicy", "iam:TagPolicy"]
    resources = [
      "arn:aws:iam::${var.expected_aws_account_id}:policy/terraformers-dev-refs-backend-aoss",
      "arn:aws:iam::${var.expected_aws_account_id}:policy/terraformers-dev-refs-codebuild",
      "arn:aws:iam::${var.expected_aws_account_id}:policy/terraformers-dev-refs-corpus-ingestion",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["terraformers-modernization"]
    }
  }

  statement {
    sid    = "AttachExactRagPolicies"
    effect = "Allow"
    actions = ["iam:AttachRolePolicy"]
    resources = [
      "arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-corpus-ingestion",
      "arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-codebuild",
      "arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-backend-aoss",
    ]
  }

  statement {
    sid    = "PassOnlyExactCodeBuildExecutionRole"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-codebuild"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["codebuild.amazonaws.com"]
    }
  }

  statement {
    sid    = "CreateExactIngestionProject"
    effect  = "Allow"
    actions = ["codebuild:CreateProject", "codebuild:TagResource"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["terraformers-modernization"]
    }
  }

  statement {
    sid    = "CreateRagAossResources"
    effect  = "Allow"
    actions = [
      "aoss:CreateCollection",
      "aoss:CreateSecurityPolicy",
      "aoss:CreateAccessPolicy",
      "aoss:CreateVpcEndpoint",
      "aoss:TagResource",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["terraformers-modernization"]
    }
  }

  statement {
    sid    = "CreateTaggedSecurityGroupsInExactVpc"
    effect  = "Allow"
    actions = ["ec2:CreateSecurityGroup"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:Vpc"
      values   = [var.rag_runtime_vpc_id]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["terraformers-modernization"]
    }
  }

  statement {
    sid    = "TagAndAuthorizeRagSecurityGroups"
    effect  = "Allow"
    actions = ["ec2:CreateTags", "ec2:AuthorizeSecurityGroupIngress"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["terraformers-modernization"]
    }
  }
}

resource "aws_iam_role_policy" "terraform_apply_rag_runtime_create" {
  name   = "terraformers-live-apply-rag-runtime-create"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply_rag_runtime_create.json
}
