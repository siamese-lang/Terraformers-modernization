#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "artifacts" / "live-stage-tfvars-builder-verification"
FIXTURES = ARTIFACTS / "fixtures"
GENERATED = ARTIFACTS / "generated"
BUILDER = ROOT / "scripts" / "deploy" / "build-live-stage-tfvars.py"


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def run(*args: str, expected: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, text=True, capture_output=True, check=False)
    if result.returncode != expected:
        raise RuntimeError(
            f"Command returned {result.returncode}, expected {expected}: {' '.join(args)}\n"
            f"stdout={result.stdout}\nstderr={result.stderr}"
        )
    return result


def assert_contains(path: Path, value: str) -> None:
    text = path.read_text(encoding="utf-8")
    if value not in text:
        raise RuntimeError(f"Expected value missing from {path}: {value}")


def assert_not_contains(path: Path, value: str) -> None:
    text = path.read_text(encoding="utf-8")
    if value in text:
        raise RuntimeError(f"Forbidden value found in {path}: {value}")


def main() -> int:
    if ARTIFACTS.exists():
        import shutil
        shutil.rmtree(ARTIFACTS)
    FIXTURES.mkdir(parents=True)
    GENERATED.mkdir(parents=True)

    network = FIXTURES / "network.json"
    runtime = FIXTURES / "runtime.json"
    stateful_outputs = FIXTURES / "stateful.json"
    foundation = FIXTURES / "foundation.json"
    write_json(network, {
        "vpc_id": {"value": "vpc-0123456789abcdef0"},
        "vpc_cidr_block": {"value": "10.40.0.0/16"},
        "private_subnet_ids": {"value": ["subnet-11111111111111111", "subnet-22222222222222222"]},
        "private_subnet_cidr_blocks": {"value": ["10.40.2.0/20", "10.40.3.0/20"]},
    })
    write_json(runtime, {
        "upload_bucket_arn": {"value": "arn:aws:s3:::terraformers-test-uploads"},
        "result_bucket_arn": {"value": "arn:aws:s3:::terraformers-test-results"},
        "ai_log_queue_arn": {"value": "arn:aws:sqs:ap-northeast-2:123456789012:terraformers-ai-log"},
        "terraform_log_queue_arn": {"value": "arn:aws:sqs:ap-northeast-2:123456789012:terraformers-terraform-log"},
        "backend_runtime_secret_arn": {"value": "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:terraformers-runtime-AbCdEf"},
    })
    write_json(stateful_outputs, {
        "database_master_user_secret_arn": {
            "value": "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:terraformers-rds-master-AbCdEf"
        },
    })
    write_json(foundation, {
        "github_oidc_provider_arn": {"value": "arn:aws:iam::123456789013:oidc-provider/token.actions.githubusercontent.com"},
        "aws_account_id": {"value": "123456789013"},
        "aws_region": {"value": "us-west-2"},
    })

    stateful = GENERATED / "stateful.tfvars"
    eks = GENERATED / "eks.tfvars"
    frontend = GENERATED / "frontend.tfvars"

    run(sys.executable, str(BUILDER), "--stage", "stateful-dependencies", "--network-outputs-json", str(network), "--output", str(stateful))
    run(sys.executable, str(BUILDER), "--stage", "eks-runtime", "--network-outputs-json", str(network), "--runtime-outputs-json", str(runtime), "--stateful-outputs-json", str(stateful_outputs), "--operator-cidr", "8.8.8.8/32", "--output", str(eks))
    run(sys.executable, str(BUILDER), "--stage", "frontend-delivery", "--foundation-outputs-json", str(foundation), "--frontend-bucket-name", "terraformers-test-frontend-123456789013", "--api-origin-load-balancer-arn", "arn:aws:elasticloadbalancing:us-west-2:123456789013:loadbalancer/app/terraformers-internal/0123456789abcdef", "--output", str(frontend))

    assert_contains(stateful, 'vpc_id = "vpc-0123456789abcdef0"')
    assert_contains(stateful, '"10.40.2.0/20"')
    assert_contains(stateful, "database_publicly_accessible      = false")
    assert_contains(eks, 'kubernetes_version = "1.35"')
    assert_contains(eks, '"8.8.8.8/32"')
    assert_contains(eks, 'upload_bucket_arn          = "arn:aws:s3:::terraformers-test-uploads"')
    assert_contains(eks, 'database_master_user_secret_arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:terraformers-rds-master-AbCdEf"')
    assert_contains(eks, "bedrock_model_resource_arns = []")
    assert_contains(frontend, 'aws_region  = "us-west-2"')
    assert_contains(frontend, 'github_oidc_provider_arn = "arn:aws:iam::123456789013:oidc-provider/token.actions.githubusercontent.com"')
    assert_contains(frontend, "frontend_bucket_force_destroy = false")
    assert_contains(frontend, "loadbalancer/app/terraformers-internal/0123456789abcdef")
    assert_contains(frontend, 'tags = {')
    assert_contains(frontend, 'Project     = "terraformers-modernization"')
    assert_contains(frontend, 'Environment = "dev"')
    assert_contains(frontend, 'ManagedBy   = "terraform"')
    assert_contains(frontend, 'CostOwner   = "siamese-lang"')
    assert_not_contains(frontend, "123456789012")

    for path in (stateful, eks, frontend):
        assert_not_contains(path, "replace-")
        assert_not_contains(path, "0.0.0.0/0")
        assert_not_contains(path, "::/0")

    rejected = run(
        sys.executable,
        str(BUILDER),
        "--stage",
        "eks-runtime",
        "--network-outputs-json",
        str(network),
        "--runtime-outputs-json",
        str(runtime),
        "--stateful-outputs-json",
        str(stateful_outputs),
        "--operator-cidr",
        "0.0.0.0/0",
        "--output",
        str(GENERATED / "unsafe.tfvars"),
        expected=1,
    )
    if "exact public IPv4 /32" not in rejected.stderr:
        raise RuntimeError("Unsafe operator CIDR rejection was not explicit.")

    missing_stateful = run(
        sys.executable,
        str(BUILDER),
        "--stage",
        "eks-runtime",
        "--network-outputs-json",
        str(network),
        "--runtime-outputs-json",
        str(runtime),
        "--operator-cidr",
        "8.8.8.8/32",
        "--output",
        str(GENERATED / "missing-stateful.tfvars"),
        expected=1,
    )
    if "stateful outputs" not in missing_stateful.stderr:
        raise RuntimeError("Missing stateful outputs rejection was not explicit.")

    missing_foundation = run(
        sys.executable,
        str(BUILDER),
        "--stage",
        "frontend-delivery",
        "--frontend-bucket-name",
        "terraformers-test-frontend-123456789013",
        "--api-origin-load-balancer-arn",
        "arn:aws:elasticloadbalancing:us-west-2:123456789013:loadbalancer/app/terraformers-internal/0123456789abcdef",
        "--output",
        str(GENERATED / "missing-foundation.tfvars"),
        expected=1,
    )
    if "foundation outputs" not in missing_foundation.stderr:
        raise RuntimeError("Missing foundation outputs rejection was not explicit.")

    oidc_mismatch = FIXTURES / "foundation-oidc-mismatch.json"
    write_json(oidc_mismatch, {
        "github_oidc_provider_arn": {"value": "arn:aws:iam::999999999999:oidc-provider/token.actions.githubusercontent.com"},
        "aws_account_id": {"value": "123456789013"},
        "aws_region": {"value": "us-west-2"},
    })
    rejected_oidc = run(
        sys.executable,
        str(BUILDER),
        "--stage",
        "frontend-delivery",
        "--foundation-outputs-json",
        str(oidc_mismatch),
        "--frontend-bucket-name",
        "terraformers-test-frontend-123456789013",
        "--api-origin-load-balancer-arn",
        "arn:aws:elasticloadbalancing:us-west-2:123456789013:loadbalancer/app/terraformers-internal/0123456789abcdef",
        "--output",
        str(GENERATED / "oidc-mismatch.tfvars"),
        expected=1,
    )
    if "github_oidc_provider_arn account" not in rejected_oidc.stderr:
        raise RuntimeError("OIDC account mismatch rejection was not explicit.")

    rejected_alb = run(
        sys.executable,
        str(BUILDER),
        "--stage",
        "frontend-delivery",
        "--foundation-outputs-json",
        str(foundation),
        "--frontend-bucket-name",
        "terraformers-test-frontend-123456789013",
        "--api-origin-load-balancer-arn",
        "arn:aws:elasticloadbalancing:us-west-2:999999999999:loadbalancer/app/terraformers-internal/0123456789abcdef",
        "--output",
        str(GENERATED / "alb-mismatch.tfvars"),
        expected=1,
    )
    if "api_origin_load_balancer_arn account" not in rejected_alb.stderr:
        raise RuntimeError("ALB account mismatch rejection was not explicit.")

    summary = [
        "live_stage_tfvars_builder_verification=passed",
        "generated_stage_count=3",
        "unsafe_operator_cidr_rejected=true",
        "missing_stateful_outputs_rejected=true",
        "missing_foundation_outputs_rejected=true",
        "oidc_account_mismatch_rejected=true",
        "alb_account_mismatch_rejected=true",
        "frontend_cost_owner_preserved=true",
        "secret_values_read=false",
        "aws_authentication=none",
        "aws_mutation=none",
    ]
    (ARTIFACTS / "verification-summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print("\n".join(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
