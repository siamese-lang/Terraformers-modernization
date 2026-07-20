data "aws_iam_policy_document" "terraform_apply_rag_runtime_create_effective" {
  source_policy_documents = [
    data.aws_iam_policy_document.terraform_apply_rag_runtime_create.json,
  ]

  statement {
    sid       = "CreateAossManagedVpcEndpointWithRegionalDependencies"
    effect    = "Allow"
    actions   = ["ec2:CreateVpcEndpoint"]
    resources = [
      "arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:subnet/*",
      "arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:security-group/*",
    ]
  }

  statement {
    sid       = "RevokeTaggedRagSecurityGroupIngress"
    effect    = "Allow"
    actions   = ["ec2:RevokeSecurityGroupIngress"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Component"
      values   = ["rag-runtime"]
    }
  }
}
