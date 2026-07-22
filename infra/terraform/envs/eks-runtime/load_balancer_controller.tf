data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_iam_policy_document" "load_balancer_controller_assume_role" {
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
      values   = ["system:serviceaccount:${var.load_balancer_controller_namespace}:${var.load_balancer_controller_service_account_name}"]
    }
  }
}

resource "aws_iam_role" "load_balancer_controller" {
  name               = "${local.name_prefix}-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.load_balancer_controller_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_policy" "load_balancer_controller" {
  name        = "${local.name_prefix}-load-balancer-controller"
  description = "Pinned AWS Load Balancer Controller v3.4.2 policy."
  policy      = file("${path.module}/policies/aws-load-balancer-controller-v3.4.2.json")
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

resource "aws_security_group" "backend_origin_alb" {
  name        = "${local.name_prefix}-backend-origin-alb"
  description = "Frontend security group for the private backend ALB used by CloudFront VPC origins."
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from the AWS-managed CloudFront origin-facing prefix list."
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]
  }

  egress {
    description = "Forward application traffic to backend Pod IPs in the runtime VPC."
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backend-origin-alb"
  })
}
