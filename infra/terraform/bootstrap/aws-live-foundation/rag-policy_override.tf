resource "aws_iam_role_policy" "terraform_apply_rag_runtime_create" {
  policy = data.aws_iam_policy_document.terraform_apply_rag_runtime_create_effective.json
}
