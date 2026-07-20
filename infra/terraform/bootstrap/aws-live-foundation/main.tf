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
    sid       = "ConfigureExactCorpusBucket"
    effect    = "Allow"
    actions   = ["s3:CreateBucket", "s3:PutBucketOwnershipControls", "s3:PutBucketPublicAccessBlock", "s3:PutEncryptionConfiguration", "s3:PutBucketVersioning", "s3:PutBucketTagging"]
    resources = ["arn:aws:s3:::${var.rag_runtime_corpus_bucket_name}"]
  }

  statement {
    sid       = "CreateTaggedRagIamRoles"
    effect    = "Allow"
    actions   = ["iam:CreateRole", "iam:TagRole"]
    resources = ["arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-corpus-ingestion", "arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-codebuild"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["Terraformers"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Component"
      values   = ["rag-runtime"]
    }
  }

  statement {
    sid       = "CreateTaggedRagIamPolicies"
    effect    = "Allow"
    actions   = ["iam:CreatePolicy", "iam:TagPolicy"]
    resources = ["arn:aws:iam::${var.expected_aws_account_id}:policy/terraformers-dev-refs-backend-aoss", "arn:aws:iam::${var.expected_aws_account_id}:policy/terraformers-dev-refs-codebuild", "arn:aws:iam::${var.expected_aws_account_id}:policy/terraformers-dev-refs-corpus-ingestion"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["Terraformers"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Component"
      values   = ["rag-runtime"]
    }
  }

  statement {
    sid       = "AttachOnlyBackendRagPolicy"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-backend-irsa-role"]
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::${var.expected_aws_account_id}:policy/terraformers-dev-refs-backend-aoss"]
    }
  }
  statement {
    sid       = "AttachOnlyCorpusIngestionPolicy"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-corpus-ingestion"]
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::${var.expected_aws_account_id}:policy/terraformers-dev-refs-corpus-ingestion"]
    }
  }
  statement {
    sid       = "AttachOnlyCodeBuildPolicy"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-codebuild"]
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::${var.expected_aws_account_id}:policy/terraformers-dev-refs-codebuild"]
    }
  }
  statement {
    sid       = "PassOnlyCodeBuildRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-codebuild"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["codebuild.amazonaws.com"]
    }
  }

  statement {
    sid     = "CreateExactCodeBuildProject"
    effect  = "Allow"
    actions = ["codebuild:CreateProject"]
    resources = [
      "arn:aws:codebuild:ap-northeast-2:${var.expected_aws_account_id}:project/terraformers-dev-refs-ingestion",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["Terraformers"]
    }

    condition {
      test     = "StringEquals"
      variable = "codebuild:serviceRole"
      values   = ["arn:aws:iam::${var.expected_aws_account_id}:role/terraformers-dev-refs-codebuild"]
    }

    condition {
      test     = "StringEquals"
      variable = "codebuild:vpcConfig.vpcId"
      values   = [var.rag_runtime_vpc_id]
    }
  }

  statement {
    sid       = "CreateExactAossCollection"
    effect    = "Allow"
    actions   = ["aoss:CreateCollection"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["Terraformers"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Component"
      values   = ["rag-runtime"]
    }
  }

  statement {
    sid       = "TagRagAossResources"
    effect    = "Allow"
    actions   = ["aoss:TagResource"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["Terraformers"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Component"
      values   = ["rag-runtime"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Project", "Environment", "Component", "ManagedBy"]
    }
  }

  statement {
    sid       = "CreateExactCollectionAossAccessPolicy"
    effect    = "Allow"
    actions   = ["aoss:CreateAccessPolicy"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aoss:collection"
      values   = ["terraformers-dev-refs"]
    }
  }

  statement {
    sid       = "CreateExactIndexAossAccessPolicy"
    effect    = "Allow"
    actions   = ["aoss:CreateAccessPolicy"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aoss:index"
      values   = ["terraformers-dev-refs/terraformers-reference-v1"]
    }
  }

  statement {
    sid       = "CreateExactAossSecurityPolicy"
    effect    = "Allow"
    actions   = ["aoss:CreateSecurityPolicy"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aoss:collection"
      values   = ["terraformers-dev-refs"]
    }
  }

  statement {
    sid       = "CreateAossVpcEndpoint"
    effect    = "Allow"
    actions   = ["aoss:CreateVpcEndpoint"]
    resources = ["*"]
  }

  # AOSS creates the underlying interface endpoint and private DNS records on
  # behalf of the caller. Keep every EC2 authorization scoped to the approved
  # RAG VPC and the AOSS regional endpoint service.
  statement {
    sid       = "CreateAossManagedVpcEndpointInApprovedVpc"
    effect    = "Allow"
    actions   = ["ec2:CreateVpcEndpoint"]
    resources = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc/${var.rag_runtime_vpc_id}"]
    condition {
      test     = "StringLike"
      variable = "ec2:VpceServiceName"
      values   = ["com.amazonaws.ap-northeast-2.aoss*"]
    }
  }

  statement {
    sid       = "CreateAossManagedVpcEndpointInApprovedSubnets"
    effect    = "Allow"
    actions   = ["ec2:CreateVpcEndpoint"]
    resources = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:subnet/*"]
    condition {
      test     = "ArnEquals"
      variable = "ec2:Vpc"
      values   = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc/${var.rag_runtime_vpc_id}"]
    }
    condition {
      test     = "StringLike"
      variable = "ec2:VpceServiceName"
      values   = ["com.amazonaws.ap-northeast-2.aoss*"]
    }
  }

  statement {
    sid       = "CreateAossManagedVpcEndpointWithTaggedSecurityGroups"
    effect    = "Allow"
    actions   = ["ec2:CreateVpcEndpoint"]
    resources = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:security-group/*"]
    condition {
      test     = "ArnEquals"
      variable = "ec2:Vpc"
      values   = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc/${var.rag_runtime_vpc_id}"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Component"
      values   = ["rag-runtime"]
    }
    condition {
      test     = "StringLike"
      variable = "ec2:VpceServiceName"
      values   = ["com.amazonaws.ap-northeast-2.aoss*"]
    }
  }

  statement {
    sid       = "CreateAossManagedVpcEndpoint"
    effect    = "Allow"
    actions   = ["ec2:CreateVpcEndpoint"]
    resources = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc-endpoint/*"]
    condition {
      test     = "StringLike"
      variable = "ec2:VpceServiceName"
      values   = ["com.amazonaws.ap-northeast-2.aoss*"]
    }
  }

  statement {
    sid       = "TagAossManagedVpcEndpointAtCreation"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc-endpoint/*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateVpcEndpoint"]
    }
  }

  statement {
    sid       = "ManageAossManagedVpcEndpoints"
    effect    = "Allow"
    actions   = ["ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint"]
    resources = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc-endpoint/*"]
  }

  statement {
    sid       = "DescribeAossManagedVpcEndpointDependencies"
    effect    = "Allow"
    actions   = ["ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeVpcEndpoints", "ec2:DescribeVpcs"]
    resources = ["*"]
  }

  statement {
    sid       = "CreateAndAssociateAossPrivateDns"
    effect    = "Allow"
    actions   = ["route53:AssociateVPCWithHostedZone", "route53:CreateHostedZone"]
    resources = ["arn:aws:route53:::hostedzone/*"]
    condition {
      test     = "ForAllValues:ArnEquals"
      variable = "route53:VPCs"
      values   = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc/${var.rag_runtime_vpc_id}"]
    }
  }

  statement {
    sid       = "ManageAossPrivateDnsRecords"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets", "route53:DeleteHostedZone", "route53:GetHostedZone", "route53:ListResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }

  statement {
    sid       = "ReadAossPrivateDnsChanges"
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid       = "ListAossPrivateDnsZones"
    effect    = "Allow"
    actions   = ["route53:ListHostedZonesByName", "route53:ListHostedZonesByVPC"]
    resources = ["*"]
    condition {
      test     = "ForAllValues:ArnEquals"
      variable = "route53:VPCs"
      values   = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc/${var.rag_runtime_vpc_id}"]
    }
  }

  statement {
    sid       = "CreateAossServiceLinkedRoleWhenAbsent"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::*:role/aws-service-role/observability.aoss.amazonaws.com/AWSServiceRoleForAmazonOpenSearchServerless"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["observability.aoss.amazonaws.com"]
    }
  }

  statement {
    sid       = "CreateSecurityGroupsInApprovedVpc"
    effect    = "Allow"
    actions   = ["ec2:CreateSecurityGroup"]
    resources = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc/${var.rag_runtime_vpc_id}"]
  }

  statement {
    sid       = "CreateTaggedRagSecurityGroups"
    effect    = "Allow"
    actions   = ["ec2:CreateSecurityGroup"]
    resources = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:security-group/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = ["Terraformers"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = ["dev"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Component"
      values   = ["rag-runtime"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Name", "Project", "Environment", "Component", "ManagedBy"]
    }
  }

  statement {
    sid       = "TagRagSecurityGroupsAtCreation"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:security-group/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateSecurityGroup"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Component"
      values   = ["rag-runtime"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Name", "Project", "Environment", "Component", "ManagedBy"]
    }
  }

  statement {
    sid    = "ManageTaggedRagSecurityGroupRules"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Component"
      values   = ["rag-runtime"]
    }
  }

}

resource "aws_iam_role_policy" "terraform_apply_rag_runtime_create" {
  name   = "terraformers-live-apply-rag-runtime-create"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply_rag_runtime_create.json
}
