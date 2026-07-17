#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ipaddress
import json
import re
import sys
from pathlib import Path
from typing import Any


class TfvarsError(RuntimeError):
    pass


def load_outputs(path: str) -> dict[str, Any]:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise TfvarsError(f"Terraform output JSON must be an object: {path}")
    return payload


def output_value(outputs: dict[str, Any], name: str) -> Any:
    if name not in outputs:
        raise TfvarsError(f"Missing Terraform output: {name}")
    raw = outputs[name]
    value = raw.get("value") if isinstance(raw, dict) else raw
    if value is None or value == "":
        raise TfvarsError(f"Terraform output is empty: {name}")
    return value


def scalar(outputs: dict[str, Any], name: str) -> str:
    value = output_value(outputs, name)
    if isinstance(value, (dict, list)):
        raise TfvarsError(f"Terraform output must be scalar: {name}")
    text = str(value)
    if any(token in text for token in ("<", ">", "replace-")) or "\n" in text or "\r" in text:
        raise TfvarsError(f"Terraform output contains an unsafe placeholder or newline: {name}")
    return text


def string_list(outputs: dict[str, Any], name: str, minimum: int = 1) -> list[str]:
    value = output_value(outputs, name)
    if not isinstance(value, list) or len(value) < minimum:
        raise TfvarsError(f"Terraform output must be a list with at least {minimum} values: {name}")
    result = [str(item) for item in value]
    if any(not item or "\n" in item or "\r" in item or "replace-" in item for item in result):
        raise TfvarsError(f"Terraform output contains an unsafe list value: {name}")
    return result


def hcl_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def hcl_list(values: list[str], indent: str = "") -> str:
    rendered = ",\n".join(f"{indent}  {hcl_string(value)}" for value in values)
    return f"[\n{rendered},\n{indent}]"


def validate_operator_cidr(value: str) -> str:
    try:
        network = ipaddress.ip_network(value, strict=True)
    except ValueError as exc:
        raise TfvarsError(f"Invalid operator CIDR: {value}") from exc
    if network.version != 4 or network.prefixlen != 32:
        raise TfvarsError("Operator CIDR must be an exact public IPv4 /32.")
    if network.is_private or network.is_loopback or network.is_link_local or network.is_multicast or network.is_reserved:
        raise TfvarsError("Operator CIDR must be a routable public IPv4 /32, not a private or documentation range.")
    return str(network)


def validate_bucket_name(value: str) -> str:
    if not (3 <= len(value) <= 63 and re.fullmatch(r"[a-z0-9][a-z0-9.-]*[a-z0-9]", value)):
        raise TfvarsError("frontend bucket name is not a valid lowercase S3 bucket name")
    if value.startswith("replace-"):
        raise TfvarsError("frontend bucket name still contains a placeholder")
    return value


def validate_alb_arn(value: str) -> str:
    pattern = r"^arn:aws[a-zA-Z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:loadbalancer/app/[^/]+/[a-zA-Z0-9]+$"
    if not re.fullmatch(pattern, value):
        raise TfvarsError("api origin must be an Application Load Balancer ARN")
    return value


def common_header(stage: str) -> list[str]:
    return [
        "# Generated from reviewed Terraform output JSON.",
        "# This file is private, is ignored by Git, and must never be uploaded as an artifact.",
        f"# target_stage={stage}",
        "",
    ]


def build_stateful(network: dict[str, Any]) -> str:
    vpc_id = scalar(network, "vpc_id")
    subnet_ids = string_list(network, "private_subnet_ids", minimum=2)
    subnet_cidrs = string_list(network, "private_subnet_cidr_blocks", minimum=2)
    lines = common_header("stateful-dependencies") + [
        'project_name = "terraformers-modernization"',
        'environment  = "dev"',
        'aws_region   = "ap-northeast-2"',
        "",
        f"vpc_id = {hcl_string(vpc_id)}",
        f"private_subnet_ids = {hcl_list(subnet_ids)}",
        "",
        "allowed_app_security_group_ids = []",
        f"allowed_database_cidr_blocks = {hcl_list(subnet_cidrs)}",
        "",
        'database_name                     = "terraformers"',
        'database_username                 = "terraformers_app"',
        'database_instance_class           = "db.t4g.micro"',
        "database_allocated_storage_gb     = 20",
        "database_max_allocated_storage_gb = 100",
        'database_engine_version           = "10.11"',
        "database_multi_az                 = false",
        "database_storage_encrypted        = true",
        "database_publicly_accessible      = false",
        "database_backup_retention_days    = 7",
        "database_deletion_protection      = false",
        "database_skip_final_snapshot      = true",
        "database_apply_immediately        = false",
        "cognito_deletion_protection       = false",
        "",
    ]
    return "\n".join(lines)


def build_eks(
    network: dict[str, Any],
    runtime: dict[str, Any],
    stateful: dict[str, Any],
    operator_cidr: str,
) -> str:
    cidr = validate_operator_cidr(operator_cidr)
    lines = common_header("eks-runtime") + [
        'project_name = "terraformers"',
        'environment  = "dev"',
        'aws_region   = "ap-northeast-2"',
        "",
        f"vpc_id         = {hcl_string(scalar(network, 'vpc_id'))}",
        f"vpc_cidr_block = {hcl_string(scalar(network, 'vpc_cidr_block'))}",
        f"private_subnet_ids = {hcl_list(string_list(network, 'private_subnet_ids', minimum=2))}",
        "",
        'kubernetes_version = "1.35"',
        "cluster_endpoint_public_access = true",
        f"cluster_endpoint_public_access_cidrs = {hcl_list([cidr])}",
        "",
        'node_instance_types = ["t3.medium"]',
        "node_disk_size      = 20",
        "node_desired_size   = 1",
        "node_min_size       = 1",
        "node_max_size       = 2",
        "",
        f"upload_bucket_arn          = {hcl_string(scalar(runtime, 'upload_bucket_arn'))}",
        f"result_bucket_arn          = {hcl_string(scalar(runtime, 'result_bucket_arn'))}",
        f"ai_log_queue_arn           = {hcl_string(scalar(runtime, 'ai_log_queue_arn'))}",
        f"terraform_log_queue_arn    = {hcl_string(scalar(runtime, 'terraform_log_queue_arn'))}",
        f"backend_runtime_secret_arn = {hcl_string(scalar(runtime, 'backend_runtime_secret_arn'))}",
        f"database_master_user_secret_arn = {hcl_string(scalar(stateful, 'database_master_user_secret_arn'))}",
        "",
        "bedrock_model_resource_arns = []",
        "",
    ]
    return "\n".join(lines)


def build_frontend(bucket_name: str, alb_arn: str) -> str:
    bucket = validate_bucket_name(bucket_name)
    alb = validate_alb_arn(alb_arn)
    lines = common_header("frontend-delivery") + [
        'environment = "dev"',
        'aws_region  = "ap-northeast-2"',
        'name_prefix = "terraformers"',
        "",
        f"frontend_bucket_name          = {hcl_string(bucket)}",
        "frontend_bucket_force_destroy = false",
        "noncurrent_version_expiration_days = 30",
        "",
        f"api_origin_load_balancer_arn = {hcl_string(alb)}",
        "aliases                       = []",
        "acm_certificate_arn            = null",
        'price_class                    = "PriceClass_200"',
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build downstream private live tfvars from reviewed outputs.")
    parser.add_argument("--stage", choices=["stateful-dependencies", "eks-runtime", "frontend-delivery"], required=True)
    parser.add_argument("--network-outputs-json")
    parser.add_argument("--runtime-outputs-json")
    parser.add_argument("--stateful-outputs-json")
    parser.add_argument("--operator-cidr")
    parser.add_argument("--frontend-bucket-name")
    parser.add_argument("--api-origin-load-balancer-arn")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    try:
        if args.stage == "stateful-dependencies":
            if not args.network_outputs_json:
                raise TfvarsError("--network-outputs-json is required")
            content = build_stateful(load_outputs(args.network_outputs_json))
        elif args.stage == "eks-runtime":
            if (
                not args.network_outputs_json
                or not args.runtime_outputs_json
                or not args.stateful_outputs_json
                or not args.operator_cidr
            ):
                raise TfvarsError(
                    "EKS generation requires network outputs, runtime outputs, stateful outputs, and operator CIDR"
                )
            content = build_eks(
                load_outputs(args.network_outputs_json),
                load_outputs(args.runtime_outputs_json),
                load_outputs(args.stateful_outputs_json),
                args.operator_cidr,
            )
        else:
            if not args.frontend_bucket_name or not args.api_origin_load_balancer_arn:
                raise TfvarsError("Frontend generation requires bucket name and internal ALB ARN")
            content = build_frontend(args.frontend_bucket_name, args.api_origin_load_balancer_arn)

        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(content.rstrip() + "\n", encoding="utf-8")
        output.chmod(0o600)
        print(f"live_stage_tfvars=generated\nstage={args.stage}\noutput={output}\naws_mutation=none")
        return 0
    except (OSError, json.JSONDecodeError, TfvarsError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
