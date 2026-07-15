locals {
  name_prefix = lower(replace("${var.project_name}-${var.environment}", "_", "-"))
  tags = merge(
    var.common_tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "aws-runtime-network"
    }
  )

  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : var.public_subnet_count) : 0
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "runtime" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_subnet" "public" {
  count = var.public_subnet_count

  vpc_id                  = aws_vpc.runtime.id
  cidr_block              = cidrsubnet(var.vpc_cidr, var.subnet_newbits, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name                                      = "${local.name_prefix}-public-${count.index + 1}"
    "kubernetes.io/role/elb"                 = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  })
}

resource "aws_subnet" "private" {
  count = var.private_subnet_count

  vpc_id            = aws_vpc.runtime.id
  cidr_block        = cidrsubnet(var.vpc_cidr, var.subnet_newbits, count.index + var.public_subnet_count)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.tags, {
    Name                                      = "${local.name_prefix}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb"        = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  })
}

resource "aws_internet_gateway" "runtime" {
  vpc_id = aws_vpc.runtime.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.runtime.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.runtime.id
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = var.public_subnet_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  })
}

resource "aws_nat_gateway" "runtime" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[var.single_nat_gateway ? 0 : count.index].id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.runtime]
}

resource "aws_route_table" "private" {
  count = var.private_subnet_count

  vpc_id = aws_vpc.runtime.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []

    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.runtime[var.single_nat_gateway ? 0 : count.index % local.nat_gateway_count].id
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
  })
}

resource "aws_route_table_association" "private" {
  count = var.private_subnet_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id          = aws_vpc.runtime.id
  service_name    = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = aws_route_table.private[*].id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-s3-endpoint"
  })
}

resource "aws_security_group" "bedrock_runtime_endpoint" {
  count = var.enable_bedrock_runtime_endpoint ? 1 : 0

  name        = "${local.name_prefix}-bedrock-runtime-endpoint-sg"
  description = "Security group for the optional Bedrock Runtime VPC endpoint."
  vpc_id      = aws_vpc.runtime.id

  ingress {
    description = "Allow HTTPS from runtime VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.runtime.cidr_block]
  }

  egress {
    description = "Allow outbound responses"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-bedrock-runtime-endpoint-sg"
  })
}

resource "aws_vpc_endpoint" "bedrock_runtime" {
  count = var.enable_bedrock_runtime_endpoint ? 1 : 0

  vpc_id              = aws_vpc.runtime.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.bedrock_runtime_endpoint[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-bedrock-runtime-endpoint"
  })
}
