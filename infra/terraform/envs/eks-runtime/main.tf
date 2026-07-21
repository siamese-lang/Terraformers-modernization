locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Component   = "terraformers-modernization"
  }
}

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_vpc_resource_controller" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "Security group attached to the Terraformers EKS control plane."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow EKS control plane egress."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

resource "aws_eks_cluster" "backend" {
  name                      = "${local.name_prefix}-backend"
  role_arn                  = aws_iam_role.eks_cluster.arn
  version                   = var.kubernetes_version
  enabled_cluster_log_types = var.enabled_cluster_log_types

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access ? var.cluster_endpoint_public_access_cidrs : null
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_cluster_vpc_resource_controller
  ]
}

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "backend" {
  cluster_name    = aws_eks_cluster.backend.name
  node_group_name = "${local.name_prefix}-backend-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types
  disk_size       = var.node_disk_size
  labels          = var.node_labels

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr
  ]
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.backend.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.backend.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

locals {
  oidc_provider_host = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

data "aws_iam_policy_document" "backend_irsa_assume_role" {
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
      values   = ["system:serviceaccount:${var.backend_namespace}:${var.backend_service_account_name}"]
    }
  }
}

resource "aws_iam_role" "backend_irsa" {
  name               = "${local.name_prefix}-backend-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.backend_irsa_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "backend_runtime_access" {
  statement {
    sid = "ReadWriteBackendBuckets"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      var.upload_bucket_arn,
      "${var.upload_bucket_arn}/*",
      var.result_bucket_arn,
      "${var.result_bucket_arn}/*"
    ]
  }

  statement {
    sid = "UseBackendQueues"
    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:SendMessage"
    ]
    resources = [
      var.ai_log_queue_arn,
      var.terraform_log_queue_arn
    ]
  }

  statement {
    sid = "ReadBackendRuntimeSecret"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [
      var.backend_runtime_secret_arn
    ]
  }

  dynamic "statement" {
    for_each = length(var.bedrock_model_resource_arns) > 0 ? [1] : []

    content {
      sid = "InvokeConfiguredBedrockModels"
      actions = [
        "bedrock:InvokeModel"
      ]
      resources = var.bedrock_model_resource_arns
    }
  }
}

resource "aws_iam_policy" "backend_runtime_access" {
  name        = "${local.name_prefix}-backend-runtime-access"
  description = "Runtime access policy for the Terraformers backend service account."
  policy      = data.aws_iam_policy_document.backend_runtime_access.json
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backend_runtime_access" {
  role       = aws_iam_role.backend_irsa.name
  policy_arn = aws_iam_policy.backend_runtime_access.arn
}

# Resolve the compatible add-on version from AWS for the configured EKS version rather
# than pinning an arbitrary historical release.
data "aws_eks_addon_version" "cloudwatch_observability" {
  addon_name         = "amazon-cloudwatch-observability"
  kubernetes_version = aws_eks_cluster.backend.version
  most_recent        = true
}

data "aws_iam_policy_document" "cloudwatch_observability_irsa_assume_role" {
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
      values   = ["system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"]
    }
  }
}

resource "aws_iam_role" "cloudwatch_observability_irsa" {
  name               = "${local.name_prefix}-cloudwatch-observability-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_observability_irsa_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability_agent" {
  role       = aws_iam_role.cloudwatch_observability_irsa.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
resource "aws_iam_role_policy_attachment" "cloudwatch_observability_xray" {
  role       = aws_iam_role.cloudwatch_observability_irsa.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name             = aws_eks_cluster.backend.name
  addon_name               = "amazon-cloudwatch-observability"
  addon_version            = data.aws_eks_addon_version.cloudwatch_observability.version
  service_account_role_arn = aws_iam_role.cloudwatch_observability_irsa.arn
  configuration_values = jsonencode({
    agent = {
      config = {
        logs = {
          metrics_collected = {
            application_signals = {}
            kubernetes = {
              enhanced_container_insights = true
            }
          }
        }
        traces = {
          traces_collected = {
            application_signals = {}
          }
        }
      }
    }
    manager = {
      applicationSignals = {
        autoMonitor = {
          monitorAllServices = false
          customSelector = {
            java = {
              deployments = ["${var.backend_namespace}/terraformers-backend"]
            }
          }
        }
      }
    }
  })
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_iam_role_policy_attachment.cloudwatch_observability_agent,
    aws_iam_role_policy_attachment.cloudwatch_observability_xray
  ]
}

# The backend publishes only its selected custom metrics to this namespace.
data "aws_iam_policy_document" "backend_cloudwatch_metrics" {
  statement {
    sid       = "PublishTerraformersBackendMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["Terraformers/Backend"]
    }
  }
}
resource "aws_iam_role_policy" "backend_cloudwatch_metrics" {
  name   = "${local.name_prefix}-backend-cloudwatch-metrics"
  role   = aws_iam_role.backend_irsa.id
  policy = data.aws_iam_policy_document.backend_cloudwatch_metrics.json
}

resource "aws_cloudwatch_dashboard" "operations_visibility" {
  dashboard_name = "${local.name_prefix}-operations-visibility"
  dashboard_body = jsonencode({
    widgets = [
      { type = "text", x = 0, y = 0, width = 24, height = 2, properties = { markdown = "# Terraformers Backend operations\nEnvironment: ${var.environment} | Service: terraformers-backend" } },
      { type = "metric", x = 0, y = 2, width = 12, height = 6, properties = { region = var.aws_region, title = "EKS node CPU / memory", view = "timeSeries", metrics = [["ContainerInsights", "node_cpu_utilization", "ClusterName", aws_eks_cluster.backend.name], ["ContainerInsights", "node_memory_utilization", "ClusterName", aws_eks_cluster.backend.name]] } },
      { type = "metric", x = 12, y = 2, width = 12, height = 6, properties = { region = var.aws_region, title = "Backend signals and availability", view = "timeSeries", metrics = [["ApplicationSignals", "Latency", "Environment", var.environment, "Service", "terraformers-backend"], ["ApplicationSignals", "Fault", "Environment", var.environment, "Service", "terraformers-backend"], ["ContainerInsights", "service_number_of_running_pods", "ClusterName", aws_eks_cluster.backend.name, "Namespace", var.backend_namespace, "Service", "terraformers-backend"]] } },
      { type = "metric", x = 0, y = 8, width = 12, height = 6, properties = { region = var.aws_region, title = "Analysis jobs and duration", view = "timeSeries", metrics = [["Terraformers/Backend", "terraformers.analysis.jobs.count", "service", "terraformers-backend", "environment", var.environment, "outcome", "started"], ["Terraformers/Backend", "terraformers.analysis.jobs.count", "service", "terraformers-backend", "environment", var.environment, "outcome", "succeeded"], ["Terraformers/Backend", "terraformers.analysis.jobs.count", "service", "terraformers-backend", "environment", var.environment, "outcome", "failed"], ["Terraformers/Backend", "terraformers.analysis.duration.avg", "service", "terraformers-backend", "environment", var.environment]] } },
      { type = "metric", x = 12, y = 8, width = 12, height = 6, properties = { region = var.aws_region, title = "Bedrock and AOSS", view = "timeSeries", metrics = [["Terraformers/Backend", "terraformers.bedrock.duration.avg", "service", "terraformers-backend", "environment", var.environment], ["Terraformers/Backend", "terraformers.aoss.duration.avg", "service", "terraformers-backend", "environment", var.environment], ["Terraformers/Backend", "terraformers.aoss.retrieved_hits.avg", "service", "terraformers-backend", "environment", var.environment]] } },
      { type = "metric", x = 0, y = 14, width = 24, height = 6, properties = { region = var.aws_region, title = "Backend container restarts", view = "timeSeries", metrics = [[{ expression = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_number_of_container_restarts\" ClusterName=\"${aws_eks_cluster.backend.name}\" Namespace=\"${var.backend_namespace}\"', 'Sum', 300)", id = "restarts", label = "pod restarts" }]] } }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "backend_fault" {
  alarm_name          = "${local.name_prefix}-backend-fault"
  alarm_description   = "Backend Application Signals fault count is non-zero."
  namespace           = "ApplicationSignals"
  metric_name         = "Fault"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { Environment = var.environment, Service = "terraformers-backend" }
}
resource "aws_cloudwatch_metric_alarm" "analysis_failure" {
  alarm_name          = "${local.name_prefix}-analysis-failures"
  alarm_description   = "Analysis job failures require investigation."
  namespace           = "Terraformers/Backend"
  metric_name         = "terraformers.analysis.jobs.count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { service = "terraformers-backend", environment = var.environment, outcome = "failed" }
}
resource "aws_cloudwatch_metric_alarm" "backend_unavailable" {
  alarm_name          = "${local.name_prefix}-backend-unavailable"
  alarm_description   = "Backend service has no running Pods."
  namespace           = "ContainerInsights"
  metric_name         = "service_number_of_running_pods"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  dimensions          = { ClusterName = aws_eks_cluster.backend.name, Namespace = var.backend_namespace, Service = "terraformers-backend" }
}
