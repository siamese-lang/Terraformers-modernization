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

  egress {
    description = "Allow outbound responses"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "database_from_security_groups" {
  for_each = toset(var.allowed_app_security_group_ids)

  security_group_id            = aws_security_group.backend_database.id
  referenced_security_group_id = each.value
  from_port                    = var.database_port
  to_port                      = var.database_port
  ip_protocol                  = "tcp"
  description                  = "Allow MariaDB from approved backend security group"
}

resource "aws_vpc_security_group_ingress_rule" "database_from_cidr_blocks" {
  for_each = toset(var.allowed_database_cidr_blocks)

  security_group_id = aws_security_group.backend_database.id
  cidr_ipv4         = each.value
  from_port         = var.database_port
  to_port           = var.database_port
  ip_protocol       = "tcp"
  description       = "Allow MariaDB from approved CIDR block"
}

resource "aws_db_subnet_group" "backend" {
  name       = "${local.name_prefix}-db"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

resource "aws_db_instance" "backend" {
  identifier = "${local.name_prefix}-mariadb"

  engine         = "mariadb"
  engine_version = var.database_engine_version
  instance_class = var.database_instance_class

  db_name  = var.database_name
  port     = var.database_port
  username = var.database_username
  password = var.database_manage_master_user_password ? null : var.database_password

  allocated_storage     = var.database_allocated_storage_gb
  max_allocated_storage = var.database_max_allocated_storage_gb
  storage_type          = var.database_storage_type
  storage_encrypted     = var.database_storage_encrypted

  multi_az                    = var.database_multi_az
  manage_master_user_password = var.database_manage_master_user_password
  publicly_accessible         = var.database_publicly_accessible

  db_subnet_group_name   = aws_db_subnet_group.backend.name
  vpc_security_group_ids = [aws_security_group.backend_database.id]

  backup_retention_period = var.database_backup_retention_days
  deletion_protection     = var.database_deletion_protection
  skip_final_snapshot     = var.database_skip_final_snapshot
  apply_immediately       = var.database_apply_immediately

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

  mfa_configuration  = "OFF"
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
