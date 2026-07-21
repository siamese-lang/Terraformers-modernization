#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

BASE_REQUIRED_TXT_VALUES = {
    "terraform_plan_risk_gate": "passed",
    "destructive_resource_count": "0",
    "replacement_resource_count": "0",
    "public_exposure_finding_count": "0",
    "optional_adapter_resource_count": "0",
    "high_cost_resource_count": "0",
}
RAG_REQUIRED_TXT_VALUES = {**BASE_REQUIRED_TXT_VALUES, "high_cost_resource_count": "1"}
BLOCKED_TYPE_PREFIXES = ("aws_security_group", "aws_vpc_security_group_")
BLOCKED_TYPES = {"aws_eks_cluster", "aws_eks_node_group"}
FOUNDATION_RESOURCES = {
    "aws_iam_role.terraform_apply": "aws_iam_role",
    "aws_iam_role_policy.terraform_apply_iam_mutation": "aws_iam_role_policy",
    "aws_iam_role_policy.terraform_apply_state_access": "aws_iam_role_policy",
    "aws_iam_role_policy_attachment.terraform_apply_read_only": "aws_iam_role_policy_attachment",
}
OPERATIONS_VISIBILITY_RESOURCES = {
    "aws_cloudwatch_dashboard.operations_visibility": "aws_cloudwatch_dashboard",
    "aws_cloudwatch_metric_alarm.analysis_failure": "aws_cloudwatch_metric_alarm",
    "aws_cloudwatch_metric_alarm.backend_fault": "aws_cloudwatch_metric_alarm",
    "aws_cloudwatch_metric_alarm.backend_unavailable": "aws_cloudwatch_metric_alarm",
    "aws_eks_addon.cloudwatch_observability": "aws_eks_addon",
    "aws_iam_role.cloudwatch_observability_irsa": "aws_iam_role",
    "aws_iam_role_policy.backend_cloudwatch_metrics": "aws_iam_role_policy",
    "aws_iam_role_policy_attachment.cloudwatch_observability_agent": "aws_iam_role_policy_attachment",
    "aws_iam_role_policy_attachment.cloudwatch_observability_xray": "aws_iam_role_policy_attachment",
}
RAG_RUNTIME_RESOURCES = {
    **{address: (resource_type, ["create"], []) for address, resource_type in {
        "aws_codebuild_project.corpus_ingestion": "aws_codebuild_project",
        "aws_iam_policy.backend_rag_runtime": "aws_iam_policy",
        "aws_iam_policy.codebuild_ingestion": "aws_iam_policy",
        "aws_iam_policy.corpus_ingestion": "aws_iam_policy",
        "aws_iam_role.codebuild_ingestion": "aws_iam_role",
        "aws_iam_role.corpus_ingestion": "aws_iam_role",
        "aws_iam_role_policy_attachment.backend_rag_runtime": "aws_iam_role_policy_attachment",
        "aws_iam_role_policy_attachment.codebuild_ingestion": "aws_iam_role_policy_attachment",
        "aws_iam_role_policy_attachment.corpus_ingestion": "aws_iam_role_policy_attachment",
        "aws_opensearchserverless_access_policy.data": "aws_opensearchserverless_access_policy",
        "aws_opensearchserverless_collection.references": "aws_opensearchserverless_collection",
        "aws_opensearchserverless_security_policy.encryption": "aws_opensearchserverless_security_policy",
        "aws_opensearchserverless_security_policy.network": "aws_opensearchserverless_security_policy",
        "aws_opensearchserverless_vpc_endpoint.collection": "aws_opensearchserverless_vpc_endpoint",
        "aws_s3_bucket.corpus": "aws_s3_bucket",
        "aws_s3_bucket_ownership_controls.corpus": "aws_s3_bucket_ownership_controls",
        "aws_s3_bucket_public_access_block.corpus": "aws_s3_bucket_public_access_block",
        "aws_s3_bucket_server_side_encryption_configuration.corpus": "aws_s3_bucket_server_side_encryption_configuration",
        "aws_s3_bucket_versioning.corpus": "aws_s3_bucket_versioning",
        "aws_security_group.aoss_vpc_endpoint": "aws_security_group",
        "aws_security_group.codebuild_ingestion": "aws_security_group",
        "aws_vpc_security_group_ingress_rule.aoss_from_backend": "aws_vpc_security_group_ingress_rule",
        "aws_vpc_security_group_ingress_rule.aoss_from_codebuild": "aws_vpc_security_group_ingress_rule",
    }.items()},
    **{address: ("aws_iam_policy_document", ["read"], []) for address in (
        "data.aws_iam_policy_document.backend_rag_runtime",
        "data.aws_iam_policy_document.codebuild_ingestion",
        "data.aws_iam_policy_document.corpus_ingestion",
    )},
}
CONTRACTS = {
    "foundation-rag-apply-permission-create": "foundation",
    "foundation-rag-apply-permission-update": "foundation",
    "foundation-operations-visibility-apply-permission-create": "foundation",
    "foundation-apply-role-bootstrap": "foundation",
    "eks-runtime-backend-policy-update": "eks-runtime",
    "eks-runtime-operations-visibility-create": "eks-runtime",
    "rag-runtime-reviewed-create": "rag-runtime",
    "rag-runtime-reviewed-recovery": "rag-runtime",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify the exact approved Terraform apply contract.")
    parser.add_argument("--summary-json", required=True, type=Path)
    parser.add_argument("--summary-txt", required=True, type=Path)
    parser.add_argument("--contract", required=True, choices=sorted(CONTRACTS))
    parser.add_argument("--stage", required=True)
    parser.add_argument("--approved-resource")
    parser.add_argument("--approved-changed-path")
    return parser.parse_args()


def read_properties(path: Path) -> dict[str, str]:
    return dict(line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines() if line and "=" in line)


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def check_risk_gates(summary: dict, txt: dict[str, str], stage: str, count: int, updates: int, required: dict[str, str] = BASE_REQUIRED_TXT_VALUES) -> None:
    expected = dict(required)
    expected.update({"plan_stage": stage, "resource_change_count": str(count), "update_resource_count": str(updates)})
    for key, value in expected.items():
        if txt.get(key) != value:
            fail(f"{key} must be {value!r}, got {txt.get(key)!r}.")
    if summary.get("stage") != stage or summary.get("resource_change_count") != count or summary.get("update_resource_count") != updates:
        fail("summary stage or resource counts do not match the approved contract.")
    for key, message in (("destructive_resources", "delete actions are not allowed."), ("replacement_resources", "replacement actions are not allowed."), ("public_exposure_findings", "public exposure findings are not allowed."), ("optional_adapter_resources", "optional adapter resource changes are not allowed.")):
        if summary.get(key): fail(message)


def actual_actions(actions: list[dict]) -> dict[str, tuple[object, object, object]]:
    return {str(item.get("address")): (item.get("type"), item.get("actions"), item.get("changed_attribute_paths")) for item in actions}


def check_blocked_types(actions: list[dict], allow_rag_security_groups: bool = False) -> None:
    allowed = {"aws_security_group", "aws_vpc_security_group_ingress_rule"} if allow_rag_security_groups else set()
    for item in actions:
        resource_type = str(item.get("type", ""))
        if (resource_type in BLOCKED_TYPES or resource_type.startswith(BLOCKED_TYPE_PREFIXES)) and resource_type not in allowed:
            fail(f"blocked resource type changed: {resource_type}.")


def check_rag_recovery_subset(summary: dict, txt: dict[str, str], actions: list[dict]) -> None:
    """Accept a state-dependent create/read subset of the reviewed RAG plan."""
    count = len(actions)
    required = {key: value for key, value in BASE_REQUIRED_TXT_VALUES.items() if key != "high_cost_resource_count"}
    update_count = sum(item.get("actions") == ["update"] for item in actions)
    if update_count not in (0, 1):
        fail("recovery may contain zero or one update resource.")
    required.update({"plan_stage": "rag-runtime", "update_resource_count": str(update_count)})
    for key, value in required.items():
        if txt.get(key) != value:
            fail(f"{key} must be {value!r}, got {txt.get(key)!r}.")
    if txt.get("resource_change_count") != str(count):
        fail("resource_change_count must match the reviewed recovery plan.")
    if summary.get("stage") != "rag-runtime" or summary.get("resource_change_count") != count or summary.get("update_resource_count") != update_count:
        fail("summary stage or resource counts do not match the recovery plan.")
    for key, message in (("destructive_resources", "delete actions are not allowed."), ("replacement_resources", "replacement actions are not allowed."), ("public_exposure_findings", "public exposure findings are not allowed."), ("optional_adapter_resources", "optional adapter resource changes are not allowed.")):
        if summary.get(key):
            fail(message)
    high_cost = summary.get("high_cost_resources")
    if high_cost not in ([], ["aws_opensearchserverless_collection.references"]):
        fail("recovery may contain only the approved AOSS collection high-cost resource.")
    if txt.get("high_cost_resource_count") != str(len(high_cost)):
        fail("high_cost_resource_count must match the reviewed recovery plan.")

    expected = RAG_RUNTIME_RESOURCES
    managed_create_found = False
    for item in actions:
        address = str(item.get("address"))
        if address not in expected:
            fail(f"recovery resource is outside the approved RAG set: {address}.")
        resource_type, expected_actions, _ = expected[address]
        is_aoss_ingress_migration = (
            address == "aws_security_group.aoss_vpc_endpoint"
            and item.get("type") == "aws_security_group"
            and item.get("actions") == ["update"]
            and item.get("changed_attribute_paths") == ["ingress"]
        )
        if not is_aoss_ingress_migration and (item.get("type") != resource_type or item.get("actions") != expected_actions):
            fail(f"recovery action does not match the approved RAG resource: {address}.")
        if item.get("actions") == ["create"]:
            managed_create_found = True
    if not managed_create_found:
        fail("recovery plan must include at least one managed resource create.")


def main() -> int:
    args = parse_args()
    if args.stage != CONTRACTS[args.contract]: fail(f"contract {args.contract!r} requires stage {CONTRACTS[args.contract]!r}.")
    txt, summary = read_properties(args.summary_txt), json.loads(args.summary_json.read_text(encoding="utf-8"))
    actions = summary.get("resource_actions") or []
    if args.contract == "foundation-rag-apply-permission-create":
        check_risk_gates(summary, txt, "foundation", 1, 0)
        expected = {"aws_iam_role_policy.terraform_apply_rag_runtime_create": ("aws_iam_role_policy", ["create"], [])}
        if actual_actions(actions) != expected: fail("foundation RAG permission resource_actions must exactly match the approved contract.")
        check_blocked_types(actions)
    elif args.contract == "foundation-rag-apply-permission-update":
        check_risk_gates(summary, txt, "foundation", 1, 1)
        expected = {"aws_iam_role_policy.terraform_apply_rag_runtime_create": ("aws_iam_role_policy", ["update"], ["policy"])}
        if actual_actions(actions) != expected: fail("foundation RAG permission update resource_actions must exactly match the approved contract.")
        check_blocked_types(actions)
    elif args.contract == "foundation-apply-role-bootstrap":
        check_risk_gates(summary, txt, "foundation", 4, 0)
        expected = {address: (kind, ["create"], []) for address, kind in FOUNDATION_RESOURCES.items()}
        if actual_actions(actions) != expected: fail("foundation resource_actions must exactly match the approved contract.")
        check_blocked_types(actions)
    elif args.contract == "foundation-operations-visibility-apply-permission-create":
        check_risk_gates(summary, txt, "foundation", 1, 0)
        expected = {"aws_iam_role_policy.terraform_apply_operations_visibility_create": ("aws_iam_role_policy", ["create"], [])}
        if actual_actions(actions) != expected: fail("foundation operations visibility permission resource_actions must exactly match the approved contract.")
        check_blocked_types(actions)
    elif args.contract == "eks-runtime-backend-policy-update":
        if not args.approved_resource or not args.approved_changed_path: fail("--approved-resource and --approved-changed-path are required for eks-runtime contract.")
        check_risk_gates(summary, txt, "eks-runtime", 1, 1)
        if actual_actions(actions) != {args.approved_resource: ("aws_iam_policy", ["update"], [args.approved_changed_path])}: fail("resource_actions must exactly match the approved contract.")
        check_blocked_types(actions)
    elif args.contract == "eks-runtime-operations-visibility-create":
        check_risk_gates(summary, txt, "eks-runtime", 9, 0)
        expected = {address: (kind, ["create"], []) for address, kind in OPERATIONS_VISIBILITY_RESOURCES.items()}
        if actual_actions(actions) != expected: fail("operations visibility resource_actions must exactly match the approved contract.")
        check_blocked_types(actions)
    elif args.contract == "rag-runtime-reviewed-create":
        check_risk_gates(summary, txt, "rag-runtime", 26, 0, RAG_REQUIRED_TXT_VALUES)
        if summary.get("high_cost_resources") != ["aws_opensearchserverless_collection.references"]: fail("rag-runtime must contain exactly the approved AOSS collection high-cost resource.")
        if actual_actions(actions) != RAG_RUNTIME_RESOURCES: fail("rag-runtime resource_actions must exactly match the approved contract.")
        check_blocked_types(actions, allow_rag_security_groups=True)
    else:
        check_rag_recovery_subset(summary, txt, actions)
        check_blocked_types(actions, allow_rag_security_groups=True)
    print("approved_terraform_apply_contract=passed")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
