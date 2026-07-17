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
    addons = json.loads(read("config/live-kubernetes-addons.json"))
    live_workflow = read(".github/workflows/aws-live-terraform-plan.yml")
    static_workflow = read(".github/workflows/terraform-static-verification.yml")
    eks_variables = read("infra/terraform/envs/eks-runtime/variables.tf")
    bootstrap_main = read("infra/terraform/bootstrap/aws-live-foundation/main.tf")
    bootstrap_variables = read("infra/terraform/bootstrap/aws-live-foundation/variables.tf")
    bootstrap_versions = read("infra/terraform/bootstrap/aws-live-foundation/versions.tf")
    bootstrap_tfvars_example = read("infra/terraform/bootstrap/aws-live-foundation/terraform.tfvars.example")
    execution_plan_doc = read("docs/live-aws-deployment-execution-plan.md")
    backend_origin_doc = read("docs/backend-origin-delivery.md")
    managed_secret_doc = read("docs/managed-secret-delivery.md")
    tfvars_builder = read("scripts/deploy/build-live-stage-tfvars.py")
    prerequisite_inventory = read("scripts/deploy/live-aws-prerequisite-inventory.py")
    prerequisite_wrapper = read("scripts/deploy/inventory-live-aws-prerequisites.sh")

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

    require(errors, "state locking             S3 native .tflock" in execution_plan_doc, "execution-plan-s3-native-locking-missing")
    require(errors, "DynamoDB lock table       not used" in execution_plan_doc, "execution-plan-dynamodb-deprecation-missing")
    require(errors, "AWS_TERRAFORM_LOCK_TABLE" not in execution_plan_doc, "execution-plan-deprecated-lock-table-variable-present")
    require(errors, "use_lockfile=true" in execution_plan_doc, "execution-plan-native-lockfile-backend-missing")
    require(errors, "terraform init -migrate-state" in execution_plan_doc, "execution-plan-bootstrap-state-migration-missing")

    require(errors, 'default     = "1.35"' in eks_variables, "eks-default-version-not-1.35")
    require(errors, '["1.34", "1.35", "1.36"]' in eks_variables, "eks-standard-support-allowlist-missing")
    require(errors, re.search(r'variable "cluster_endpoint_public_access"[\s\S]*?default\s*=\s*false', eks_variables) is not None, "eks-public-endpoint-not-private-default")
    require(errors, 'cidr != "0.0.0.0/0"' in eks_variables, "eks-ipv4-world-open-guard-missing")
    require(errors, 'cidr != "::/0"' in eks_variables, "eks-ipv6-world-open-guard-missing")

    require(errors, 'required_version = ">= 1.15.0, < 2.0.0"' in bootstrap_versions, "bootstrap-terraform-version-drift")
    require(errors, "allowed_account_ids = [var.expected_aws_account_id]" in bootstrap_versions, "bootstrap-provider-account-allowlist-missing")
    require(errors, re.search(r'variable "expected_aws_account_id"[\s\S]*?\^\[0-9\]\{12\}\$', bootstrap_variables) is not None, "bootstrap-expected-account-validation-missing")
    require(errors, 'expected_aws_account_id = "000000000000"' in bootstrap_tfvars_example, "bootstrap-expected-account-placeholder-missing")
    require(errors, "data.aws_caller_identity.current.account_id == var.expected_aws_account_id" in bootstrap_main, "bootstrap-caller-account-precondition-missing")
    require(errors, "existing_github_oidc_provider_arn must belong to expected_aws_account_id" in bootstrap_main, "bootstrap-existing-oidc-account-guard-missing")
    require(errors, "prevent_destroy = true" in bootstrap_main, "state-bucket-prevent-destroy-missing")
    require(errors, "block_public_acls       = true" in bootstrap_main, "state-bucket-public-block-missing")
    require(errors, 'status = "Enabled"' in bootstrap_main, "state-bucket-versioning-missing")
    require(errors, 'sse_algorithm = "AES256"' in bootstrap_main, "state-bucket-encryption-missing")
    require(errors, 'policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"' in bootstrap_main, "plan-role-readonly-policy-missing")
    require(errors, 'variable = "token.actions.githubusercontent.com:aud"' in bootstrap_main, "oidc-audience-condition-missing")
    require(errors, 'variable = "token.actions.githubusercontent.com:sub"' in bootstrap_main, "oidc-subject-condition-missing")
    require(errors, '!strcontains(subject, "*")' in bootstrap_variables, "oidc-wildcard-subject-guard-missing")
    require(errors, contract.get("github_oidc_subject") in bootstrap_variables, "oidc-subject-contract-drift")
    require(errors, "expected-account-id-required" in prerequisite_inventory, "prerequisite-expected-account-required-guard-missing")
    require(errors, "expected = args.expected_account_id" in prerequisite_inventory, "prerequisite-expected-account-explicit-use-missing")
    require(errors, "args.expected_account_id or account" not in prerequisite_inventory, "prerequisite-implicit-account-acceptance-present")

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

    expected_examples = {stage["id"] for stage in contract.get("terraform_stages", [])}
    require(errors, expected_examples == set(examples), "live-tfvars-example-stage-drift")

    expected_stage_secret_mapping = {
        "network": ["AWS_LIVE_NETWORK_TFVARS_B64"],
        "runtime-dependencies": ["AWS_LIVE_RUNTIME_DEPENDENCIES_TFVARS_B64"],
        "stateful-dependencies": ["AWS_LIVE_STATEFUL_DEPENDENCIES_TFVARS_B64"],
        "eks-runtime": ["AWS_LIVE_EKS_TFVARS_B64"],
        "frontend-delivery": ["AWS_LIVE_FRONTEND_TFVARS_B64"],
    }
    stage_secret_mapping = contract.get("required_github_secrets_by_stage", {})
    mapped_secrets = [secret for secrets in stage_secret_mapping.values() for secret in secrets]
    require(errors, contract.get("schema_version") == 3, "live-prerequisite-schema-version-drift")
    require(errors, stage_secret_mapping == expected_stage_secret_mapping, "stage-secret-mapping-drift")
    require(
        errors,
        sorted(mapped_secrets) == sorted(contract.get("required_github_secrets", [])),
        "stage-secret-set-drift",
    )
    require(errors, 'STAGE="network"' in prerequisite_wrapper, "prerequisite-wrapper-network-default-missing")
    require(errors, "required_github_secrets_by_stage" in prerequisite_wrapper, "prerequisite-wrapper-stage-map-missing")
    require(errors, 'contract["required_github_secrets"] = selected' in prerequisite_wrapper, "prerequisite-wrapper-stage-filter-missing")

    addon_items = addons.get("addons", {})
    lbc = addon_items.get("aws-load-balancer-controller", {})
    eso = addon_items.get("external-secrets", {})
    require(errors, addons.get("eks_kubernetes_version") == "1.35", "addon-eks-version-drift")
    require(errors, lbc.get("chart_version") == "3.4.2", "load-balancer-controller-version-drift")
    require(errors, lbc.get("controller_image") == "public.ecr.aws/eks/aws-load-balancer-controller:v3.4.2", "load-balancer-controller-image-drift")
    require(errors, lbc.get("service_account_create") is False, "load-balancer-controller-service-account-create-enabled")
    require(errors, lbc.get("iam_policy_file") == "infra/terraform/envs/eks-runtime/policies/aws-load-balancer-controller-v3.4.2.json", "load-balancer-controller-policy-drift")
    require(errors, "chart: eks/aws-load-balancer-controller 3.4.2" in backend_origin_doc, "load-balancer-controller-doc-drift")

    require(errors, eso.get("chart_version") == "2.7.0", "external-secrets-version-drift")
    require(errors, eso.get("controller_service_account") == "external-secrets", "external-secrets-controller-service-account-drift")
    require(errors, eso.get("controller_service_account_create") is True, "external-secrets-controller-service-account-not-created")
    require(errors, eso.get("provider_auth_namespace") == "terraformers-runtime", "external-secrets-provider-auth-namespace-drift")
    require(errors, eso.get("provider_auth_service_account") == "terraformers-external-secrets", "external-secrets-provider-auth-service-account-drift")
    require(errors, eso.get("provider_auth_service_account_create_by_helm") is False, "external-secrets-provider-auth-created-by-helm")
    require(errors, eso.get("helm_install_crds") is False, "external-secrets-helm-crd-install-enabled")
    require(errors, eso.get("crd_installation") == "pinned-server-side-apply-before-helm", "external-secrets-crd-strategy-drift")
    require(errors, "/v2.7.0/deploy/crds/bundle.yaml" in str(eso.get("crd_bundle_url", "")), "external-secrets-crd-url-drift")
    require(errors, "External Secrets Operator chart: 2.7.0" in managed_secret_doc, "external-secrets-version-missing")
    require(errors, "controller ServiceAccount: external-secrets" in managed_secret_doc, "external-secrets-controller-doc-drift")
    require(errors, "provider-auth ServiceAccount: terraformers-runtime/terraformers-external-secrets" in managed_secret_doc, "external-secrets-provider-auth-doc-drift")

    require(errors, 'choices=["stateful-dependencies", "eks-runtime", "frontend-delivery"]' in tfvars_builder, "tfvars-builder-stage-contract-drift")
    require(errors, 'parser.add_argument("--stateful-outputs-json")' in tfvars_builder, "tfvars-builder-stateful-output-input-missing")
    require(errors, "scalar(stateful, 'database_master_user_secret_arn')" in tfvars_builder, "tfvars-builder-database-secret-handoff-missing")
    require(errors, "Operator CIDR must be an exact public IPv4 /32." in tfvars_builder, "tfvars-builder-operator-cidr-guard-missing")
    require(errors, "database_publicly_accessible      = false" in tfvars_builder, "tfvars-builder-public-database-guard-missing")
    require(errors, "bedrock_model_resource_arns = []" in tfvars_builder, "tfvars-builder-optional-adapter-guard-missing")
    require(errors, "frontend_bucket_force_destroy = false" in tfvars_builder, "tfvars-builder-force-destroy-guard-missing")

    report = {
        "pre_live_aws_readiness": "passed" if not errors else "failed",
        "terraform_cli_version": contract.get("terraform_cli_version"),
        "state_locking": contract.get("state_locking"),
        "execution_plan_locking_aligned": not any(error.startswith("execution-plan-") for error in errors),
        "stage_aware_prerequisites": stage_secret_mapping == expected_stage_secret_mapping,
        "eks_default_version": "1.35",
        "eks_endpoint_default": "private",
        "live_egress_baseline": "single-nat-gateway",
        "load_balancer_controller_version": lbc.get("chart_version"),
        "external_secrets_version": eso.get("chart_version"),
        "tfvars_example_count": len(examples),
        "generated_handoff_stage_count": 3,
        "github_oidc_subject": contract.get("github_oidc_subject"),
        "bootstrap_expected_account_required": True,
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
        f"execution_plan_locking_aligned={str(report['execution_plan_locking_aligned']).lower()}",
        f"stage_aware_prerequisites={str(report['stage_aware_prerequisites']).lower()}",
        f"eks_default_version={report['eks_default_version']}",
        f"eks_endpoint_default={report['eks_endpoint_default']}",
        f"live_egress_baseline={report['live_egress_baseline']}",
        f"load_balancer_controller_version={report['load_balancer_controller_version']}",
        f"external_secrets_version={report['external_secrets_version']}",
        f"tfvars_example_count={report['tfvars_example_count']}",
        f"generated_handoff_stage_count={report['generated_handoff_stage_count']}",
        "bootstrap_expected_account_required=true",
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
