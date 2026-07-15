output "database_security_group_id" {
  description = "Security group ID attached to the backend MariaDB database."
  value       = aws_security_group.backend_database.id
}

output "database_subnet_group_name" {
  description = "DB subnet group name attached to the backend MariaDB database."
  value       = aws_db_subnet_group.backend.name
}

output "database_instance_id" {
  description = "RDS MariaDB instance ID."
  value       = aws_db_instance.backend.id
}

output "database_instance_arn" {
  description = "RDS MariaDB instance ARN."
  value       = aws_db_instance.backend.arn
}

output "database_endpoint" {
  description = "RDS MariaDB endpoint hostname."
  value       = aws_db_instance.backend.address
  sensitive   = true
}

output "database_port" {
  description = "RDS MariaDB endpoint port."
  value       = aws_db_instance.backend.port
}

output "database_name" {
  description = "Application database name."
  value       = var.database_name
}

output "database_username" {
  description = "Application database username."
  value       = aws_db_instance.backend.username
  sensitive   = true
}

output "spring_datasource_url" {
  description = "JDBC URL for SPRING_DATASOURCE_URL."
  value       = "jdbc:mariadb://${aws_db_instance.backend.address}:${aws_db_instance.backend.port}/${var.database_name}?${var.database_jdbc_ssl_params}"
  sensitive   = true
}

output "cognito_region" {
  description = "Cognito region for COGNITO_REGION."
  value       = var.aws_region
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID for COGNITO_USER_POOL_ID."
  value       = aws_cognito_user_pool.backend.id
}

output "cognito_user_pool_client_id" {
  description = "Cognito app client ID for COGNITO_USER_POOL_CLIENT_ID."
  value       = aws_cognito_user_pool_client.backend.id
}

output "cognito_jwks_url" {
  description = "Cognito JWKS URL for COGNITO_JWKS_URL."
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.backend.id}/.well-known/jwks.json"
}
