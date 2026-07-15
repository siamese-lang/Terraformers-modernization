locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))
  tags = merge(
    var.common_tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "backend-stateful-dependencies"
    }
  )
}

resource "aws_security_group" "backend_database" {
  name        = "${local.name_prefix}-db"
  description = "Allow backend runtime to connect to the Terraformers MariaDB database."
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = toset(var.allowed_app_security_group_ids)
    content {
      description     = "MariaDB from backend security group"
      from_port       = 3306
      to_port         = 3306
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = toset(var.allowed_database_cidr_blocks)
    content {
      description = "MariaDB from approved CIDR"
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "Allow outbound responses"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_db_subnet_group" "backend" {
  name       = "${local.name_prefix}-db"
  subnet_ids = var.private_subnet_ids

  tags = local.tags
}

resource "aws_db_instance" "backend" {
  identifier = "${local.name_prefix}-mariadb"

  engine         = "mariadb"
  engine_version = var.database_engine_version
  instance_class = var.database_instance_class

  allocated_storage     = var.database_allocated_storage_gb
  max_allocated_storage = max(var.database_allocated_storage_gb, 100)
  storage_encrypted     = true

  db_name  = var.database_name
  username = var.database_username
  password = var.database_password

  db_subnet_group_name   = aws_db_subnet_group.backend.name
  vpc_security_group_ids = [aws_security_group.backend_database.id]
  publicly_accessible    = false

  backup_retention_period = var.database_backup_retention_days
  deletion_protection     = var.database_deletion_protection
  skip_final_snapshot     = var.database_skip_final_snapshot
  apply_immediately       = true

  tags = local.tags
}

resource "aws_cognito_user_pool" "backend" {
  name = "${local.name_prefix}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  mfa_configuration   = "OFF"
  deletion_protection = var.cognito_deletion_protection ? "ACTIVE" : "INACTIVE"

  tags = local.tags
}

resource "aws_cognito_user_pool_client" "backend" {
  name         = "${local.name_prefix}-backend-client"
  user_pool_id = aws_cognito_user_pool.backend.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  prevent_user_existence_errors = "ENABLED"
  supported_identity_providers  = ["COGNITO"]
}
