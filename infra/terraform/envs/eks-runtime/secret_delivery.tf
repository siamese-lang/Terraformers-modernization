variable "database_master_user_secret_arn" {
  description = "RDS-managed Secrets Manager secret ARN containing the database master password."
  type        = string
}

variable "external_secrets_service_account_name" {
  description = "Dedicated Kubernetes ServiceAccount used by External Secrets to read approved runtime secrets."
  type        = string
  default     = "terraformers-external-secrets"
}

data "aws_iam_policy_document" "external_secrets_irsa_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values = [
        "system:serviceaccount:${var.backend_namespace}:${var.external_secrets_service_account_name}"
      ]
    }
  }
}

resource "aws_iam_role" "external_secrets_irsa" {
  name               = "${local.name_prefix}-external-secrets-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_irsa_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "external_secrets_read" {
  statement {
    sid = "ReadApprovedRuntimeSecrets"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      var.backend_runtime_secret_arn,
      var.database_master_user_secret_arn
    ]
  }
}

resource "aws_iam_policy" "external_secrets_read" {
  name        = "${local.name_prefix}-external-secrets-read"
  description = "Read-only access to the backend runtime config secret and RDS-managed credential secret."
  policy      = data.aws_iam_policy_document.external_secrets_read.json
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "external_secrets_read" {
  role       = aws_iam_role.external_secrets_irsa.name
  policy_arn = aws_iam_policy.external_secrets_read.arn
}
