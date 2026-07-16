#!/usr/bin/env python3
"""Render the private ALB/CloudFront VPC-origin deployment package.

The renderer consumes public Terraform output metadata only. It does not contact
AWS, install Helm charts, apply Kubernetes resources, or create load balancers.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


class PackageError(RuntimeError):
    pass


REQUIRED_OUTPUTS = (
    "cluster_name",
    "aws_region",
    "vpc_id",
    "load_balancer_controller_namespace",
    "load_balancer_controller_service_account_name",
    "load_balancer_controller_irsa_role_arn",
    "backend_origin_alb_security_group_id",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render the private backend origin package.")
    parser.add_argument("--eks-outputs-json", required=True)
    parser.add_argument(
        "--template-dir",
        default="infra/kubernetes/aws-runtime-origin",
    )
    parser.add_argument(
        "--output-dir",
        default="artifacts/backend-origin-package",
    )
    return parser.parse_args()


def load_outputs(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def output_value(outputs: dict[str, Any], name: str) -> str:
    if name not in outputs:
        raise PackageError(f"Missing Terraform output: {name}")
    raw = outputs[name]
    value = raw.get("value") if isinstance(raw, dict) else raw
    if value is None or value == "":
        raise PackageError(f"Terraform output is empty: {name}")
    if isinstance(value, (dict, list)):
        raise PackageError(f"Terraform output must be scalar: {name}")
    text = str(value)
    if "<" in text or ">" in text:
        raise PackageError(f"Terraform output contains a placeholder: {name}")
    return text


def render(template: str, replacements: dict[str, str]) -> str:
    rendered = template
    for token, value in replacements.items():
        rendered = rendered.replace(token, value)
    unresolved = sorted(part for part in rendered.split() if part.startswith("__") and part.endswith("__"))
    if unresolved:
        raise PackageError("Unresolved template tokens: " + ", ".join(unresolved))
    return rendered


def main() -> int:
    args = parse_args()
    outputs = load_outputs(Path(args.eks_outputs_json))
    values = {name: output_value(outputs, name) for name in REQUIRED_OUTPUTS}

    cluster_name = values["cluster_name"]
    base_name = cluster_name.removesuffix("-backend")
    load_balancer_name = f"{base_name}-origin"[:32].rstrip("-")
    environment = base_name.split("-")[-1] if "-" in base_name else "dev"

    replacements = {
        "__EKS_CLUSTER_NAME__": cluster_name,
        "__AWS_REGION__": values["aws_region"],
        "__VPC_ID__": values["vpc_id"],
        "__LOAD_BALANCER_CONTROLLER_NAMESPACE__": values["load_balancer_controller_namespace"],
        "__LOAD_BALANCER_CONTROLLER_SERVICE_ACCOUNT__": values["load_balancer_controller_service_account_name"],
        "__LOAD_BALANCER_CONTROLLER_IRSA_ROLE_ARN__": values["load_balancer_controller_irsa_role_arn"],
        "__BACKEND_ORIGIN_ALB_SECURITY_GROUP_ID__": values["backend_origin_alb_security_group_id"],
        "__BACKEND_ORIGIN_LOAD_BALANCER_NAME__": load_balancer_name,
        "__ENVIRONMENT__": environment,
    }

    template_dir = Path(args.template_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    templates = {
        "aws-load-balancer-controller-serviceaccount.yaml": "aws-load-balancer-controller-serviceaccount.yaml",
        "aws-load-balancer-controller-values.yaml": "aws-load-balancer-controller-values.yaml",
        "backend-origin-ingress.yaml": "backend-origin-ingress.yaml",
    }
    for source_name, target_name in templates.items():
        source = template_dir / source_name
        if not source.is_file():
            raise PackageError(f"Missing template: {source}")
        target = output_dir / target_name
        target.write_text(render(source.read_text(encoding="utf-8"), replacements), encoding="utf-8")

    source_map = {
        "cluster_name": "eks-runtime.cluster_name",
        "controller_identity": "eks-runtime.load_balancer_controller_irsa_role_arn",
        "frontend_security_group": "eks-runtime.backend_origin_alb_security_group_id",
        "load_balancer_scheme": "internal",
        "target_type": "ip",
        "cloudfront_origin_mode": "vpc-origin",
        "public_alb": False,
        "aws_mutation": "not-performed",
    }
    (output_dir / "backend-origin-source-map.json").write_text(
        json.dumps(source_map, indent=2) + "\n", encoding="utf-8"
    )

    summary = [
        "backend_origin_package=generated",
        "load_balancer_controller_chart_version=3.4.2",
        "load_balancer_scheme=internal",
        "load_balancer_target_type=ip",
        "load_balancer_listener=HTTP:80-private",
        "load_balancer_healthcheck=/actuator/health",
        "cloudfront_origin_mode=vpc-origin",
        "cloudfront_origin_prefix_list=managed",
        "public_alb=false",
        "controller_installation=required-not-performed",
        "kubernetes_apply=none",
        "aws_mutation=none",
    ]
    (output_dir / "package-summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")

    apply_order = f"""# Manual, approval-gated private backend origin sequence
# This package renderer did not execute any command below.

kubectl apply -f {output_dir / 'aws-load-balancer-controller-serviceaccount.yaml'}
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \\
  --namespace {values['load_balancer_controller_namespace']} \\
  --version 3.4.2 \\
  --values {output_dir / 'aws-load-balancer-controller-values.yaml'}

kubectl rollout status deployment/aws-load-balancer-controller \\
  --namespace {values['load_balancer_controller_namespace']}

kubectl apply -f {output_dir / 'backend-origin-ingress.yaml'}
kubectl wait --namespace terraformers-runtime \\
  --for=jsonpath='{{.status.loadBalancer.ingress[0].hostname}}' \\
  ingress/terraformers-backend-origin \\
  --timeout=10m

# Resolve the controller-created internal ALB before applying frontend-delivery Terraform.
aws elbv2 describe-load-balancers \\
  --names {load_balancer_name} \\
  --region {values['aws_region']} \\
  --query 'LoadBalancers[0].{{LoadBalancerArn:LoadBalancerArn,DNSName:DNSName,Scheme:Scheme,State:State.Code}}'

# Supply the returned LoadBalancerArn as frontend-delivery.api_origin_load_balancer_arn.
# Then create the CloudFront VPC origin and distribution through an approved Terraform plan/apply.
"""
    (output_dir / "apply-order.txt").write_text(apply_order, encoding="utf-8")

    print("\n".join(summary))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (PackageError, OSError, json.JSONDecodeError) as exc:
        print(str(exc), file=__import__("sys").stderr)
        raise SystemExit(1)
