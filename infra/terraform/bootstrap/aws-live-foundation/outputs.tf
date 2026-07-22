output "aws_account_id" {
  description = "AWS account ID where the live foundation was created."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region for state storage."
  value       = var.aws_region
}

output "terraform_state_bucket" {
  description = "Versioned private S3 bucket used by stage-specific Terraform state."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "terraform_state_prefix" {
  description = "Prefix used for stage-specific state and native .tflock objects."
  value       = local.normalized_state_prefix
}

output "terraform_state_locking" {
  description = "State locking mode required by the live planning workflow."
  value       = "s3-native-lockfile"
}

output "github_oidc_provider_arn" {
  description = "IAM OIDC provider used by GitHub Actions."
  value       = local.github_oidc_provider_arn
}

output "terraform_plan_role_arn" {
  description = "Read-only AWS role assumed by the protected GitHub environment."
  value       = aws_iam_role.terraform_plan.arn
}

output "github_oidc_subjects" {
  description = "Exact GitHub OIDC subjects trusted by the plan role."
  value       = var.github_oidc_subjects
}

output "terraform_apply_role_arn" {
  description = "Approved apply AWS role assumed by the protected GitHub environment."
  value       = aws_iam_role.terraform_apply.arn
}

output "terraform_apply_github_environment" {
  description = "Protected GitHub environment trusted by the apply role."
  value       = var.apply_github_environment
}

output "terraform_apply_oidc_subject" {
  description = "Exact GitHub OIDC subject trusted by the apply role."
  value       = local.terraform_apply_oidc_subject
}

output "terraform_apply_target_policy_arn" {
  description = "Exact customer-managed IAM policy the apply role may update."
  value       = var.approved_apply_iam_policy_arn
}
