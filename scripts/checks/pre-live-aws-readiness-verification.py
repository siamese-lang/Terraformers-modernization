#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_DIR = ROOT / "artifacts" / "pre-live-aws-readiness"
SUMMARY = EVIDENCE_DIR / "verification-summary.txt"
REPORT = EVIDENCE_DIR / "verification-report.json"


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise FileNotFoundError(relative)
    return path.read_text(encoding="utf-8")


def require(errors: list[str], condition: bool, code: str) -> None:
    if not condition:
        errors.append(code)


def main() -> int:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []

    contract = json.loads(read("config/live-aws-prerequisites.json"))
    live_workflow = read(".github/workflows/aws-live-terraform-plan.yml")
    static_workflow = read(".github/workflows/terraform-static-verification.yml")
    eks_variables = read("infra/terraform/envs/eks-runtime/variables.tf")
    bootstrap_main = read("infra/terraform/bootstrap/aws-live-foundation/main.tf")
    bootstrap_variables = read("infra/terraform/bootstrap/aws-live-foundation/variables.tf")
    bootstrap_versions = read("infra/terraform/bootstrap/aws-live-foundation/versions.tf")

    examples = {
        "network": read("infra/terraform/envs/aws-runtime-network/live.tfvars.example"),
        "runtime-dependencies": read("infra/terraform/envs/backend-runtime-dependencies/live.tfvars.example"),
        "stateful-dependencies": read("infra/terraform/envs/backend-stateful-dependencies/live.tfvars.example"),
        "eks-runtime": read("infra/terraform/envs/eks-runtime/live.tfvars.example"),
        "frontend-delivery": read("infra/terraform/envs/frontend-delivery/live.tfvars.example"),
    }

    require(errors, contract.get("terraform_cli_version") == "1.15.8", "terraform-cli-contract-drift")
    require(errors, contract.get("state_locking") == "s3-native-lockfile", "state-locking-contract-drift")
    require(errors, "terraform_version: 1.15.8" in live_workflow, "live-workflow-terraform-version-drift")
    require(errors, "terraform_version: 1.15.8" in static_workflow, "static-workflow-terraform-version-drift")
    require(errors, "use_lockfile = true" in live_workflow, "s3-native-lockfile-missing")
    require(errors, "dynamodb_table" not in live_workflow, "deprecated-dynamodb-locking-present")
    require(errors, "AWS_TERRAFORM_LOCK_TABLE" not in live_workflow, "deprecated-lock-table-variable-present")
    require(errors, "AWS_ROLE_TO_ASSUME: ${{ vars.AWS_ROLE_TO_ASSUME }}" in live_workflow, "oidc-role-not-environment-variable")

    require(errors, 'default     = "1.35"' in eks_variables, "eks-default-version-not-1.35")
    require(errors, '["1.34", "1.35", "1.36"]' in eks_variables, "eks-standard-support-allowlist-missing")
    require(errors, re.search(r'variable "cluster_endpoint_public_access"[\s\S]*?default\s*=\s*false', eks_variables) is not None, "eks-public-endpoint-not-private-default")
    require(errors, 'cidr != "0.0.0.0/0"' in eks_variables, "eks-ipv4-world-open-guard-missing")
    require(errors, 'cidr != "::/0"' in eks_variables, "eks-ipv6-world-open-guard-missing")

    require(errors, 'required_version = ">= 1.15.0, < 2.0.0"' in bootstrap_versions, "bootstrap-terraform-version-drift")
    require(errors, "prevent_destroy = true" in bootstrap_main, "state-bucket-prevent-destroy-missing")
    require(errors, "block_public_acls       = true" in bootstrap_main, "state-bucket-public-block-missing")
    require(errors, 'status = "Enabled"' in bootstrap_main, "state-bucket-versioning-missing")
    require(errors, 'sse_algorithm = "AES256"' in bootstrap_main, "state-bucket-encryption-missing")
    require(errors, 'policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"' in bootstrap_main, "plan-role-readonly-policy-missing")
    require(errors, 'variable = "token.actions.githubusercontent.com:aud"' in bootstrap_main, "oidc-audience-condition-missing")
    require(errors, 'variable = "token.actions.githubusercontent.com:sub"' in bootstrap_main, "oidc-subject-condition-missing")
    require(errors, '!strcontains(subject, "*")' in bootstrap_variables, "oidc-wildcard-subject-guard-missing")
    require(errors, contract.get("github_oidc_subject") in bootstrap_variables, "oidc-subject-contract-drift")

    require(errors, "enable_nat_gateway = true" in examples["network"], "live-network-nat-not-explicit")
    require(errors, "single_nat_gateway = true" in examples["network"], "live-network-single-nat-not-explicit")
    require(errors, "enable_bedrock_runtime_endpoint = false" in examples["network"], "optional-bedrock-endpoint-enabled")
    require(errors, 'kubernetes_version = "1.35"' in examples["eks-runtime"], "live-eks-version-not-1.35")
    require(errors, "cluster_endpoint_public_access = true" in examples["eks-runtime"], "operator-access-path-not-explicit")
    require(errors, '"203.0.113.10/32"' in examples["eks-runtime"], "operator-cidr-placeholder-missing")
    require(errors, "bedrock_model_resource_arns = []" in examples["eks-runtime"], "optional-bedrock-models-enabled")
    require(errors, "database_publicly_accessible          = false" in examples["stateful-dependencies"], "database-public-access-enabled")
    require(errors, "database_storage_encrypted            = true" in examples["stateful-dependencies"], "database-encryption-disabled")
    require(errors, "frontend_bucket_force_destroy = false" in examples["frontend-delivery"], "frontend-force-destroy-enabled")

    expected_examples = set(contract.get("terraform_stages", []).__len__() and [stage["id"] for stage in contract["terraform_stages"]])
    require(errors, expected_examples == set(examples), "live-tfvars-example-stage-drift")

    report = {
        "pre_live_aws_readiness": "passed" if not errors else "failed",
        "terraform_cli_version": contract.get("terraform_cli_version"),
        "state_locking": contract.get("state_locking"),
        "eks_default_version": "1.35",
        "eks_endpoint_default": "private",
        "live_egress_baseline": "single-nat-gateway",
        "tfvars_example_count": len(examples),
        "github_oidc_subject": contract.get("github_oidc_subject"),
        "deprecated_dynamodb_locking": False,
        "optional_adapters_enabled": False,
        "aws_authentication": "none",
        "aws_mutation": "none",
        "errors": errors,
    }
    REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    summary = [
        f"pre_live_aws_readiness={report['pre_live_aws_readiness']}",
        f"terraform_cli_version={report['terraform_cli_version']}",
        f"state_locking={report['state_locking']}",
        f"eks_default_version={report['eks_default_version']}",
        f"eks_endpoint_default={report['eks_endpoint_default']}",
        f"live_egress_baseline={report['live_egress_baseline']}",
        f"tfvars_example_count={report['tfvars_example_count']}",
        "deprecated_dynamodb_locking=false",
        "optional_adapters_enabled=false",
        "aws_authentication=none",
        "aws_mutation=none",
    ]
    SUMMARY.write_text("\n".join(summary) + "\n", encoding="utf-8")
    print("\n".join(summary))
    for error in errors:
        print(f"[pre-live-aws-readiness] {error}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
