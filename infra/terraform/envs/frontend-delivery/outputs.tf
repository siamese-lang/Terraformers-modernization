output "frontend_bucket_name" {
  description = "Private S3 bucket containing the React production bundle."
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_bucket_arn" {
  description = "ARN of the private frontend bundle bucket."
  value       = aws_s3_bucket.frontend.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID used for frontend cache invalidation."
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the frontend CloudFront distribution."
  value       = aws_cloudfront_distribution.frontend.arn
}

output "cloudfront_distribution_domain_name" {
  description = "Default CloudFront domain serving the React SPA and /api/* proxy."
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "frontend_base_url" {
  description = "HTTPS base URL for browser access when no custom alias is used."
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "frontend_api_base_url" {
  description = "Same-origin browser API base. The React client intentionally uses relative /api paths."
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}/api"
}

output "frontend_origin_access_control_id" {
  description = "CloudFront OAC ID that protects the private frontend bucket."
  value       = aws_cloudfront_origin_access_control.frontend.id
}
