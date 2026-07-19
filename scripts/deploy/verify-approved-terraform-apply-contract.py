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
BLOCKED_TYPE_PREFIXES = ("aws_security_group", "aws_vpc_security_group_")
BLOCKED_TYPES = {"aws_eks_cluster", "aws_eks_node_group"}
FOUNDATION_RESOURCES = {
    "aws_iam_role.terraform_apply": "aws_iam_role",
    "aws_iam_role_policy.terraform_apply_iam_mutation": "aws_iam_role_policy",
    "aws_iam_role_policy.terraform_apply_state_access": "aws_iam_role_policy",
    "aws_iam_role_policy_attachment.terraform_apply_read_only": "aws_iam_role_policy_attachment",
}
CONTRACTS = {
    "foundation-apply-role-bootstrap": "foundation",
    "eks-runtime-backend-policy-update": "eks-runtime",
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
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def check_risk_gates(summary: dict, txt: dict[str, str], stage: str, count: int, updates: int) -> None:
    required = dict(BASE_REQUIRED_TXT_VALUES)
    required.update({"plan_stage": stage, "resource_change_count": str(count), "update_resource_count": str(updates)})
    for key, expected in required.items():
        if txt.get(key) != expected:
            fail(f"{key} must be {expected!r}, got {txt.get(key)!r}.")
    if summary.get("stage") != stage:
        fail(f"summary stage must be {stage!r}.")
    if summary.get("resource_change_count") != count or summary.get("update_resource_count") != updates:
        fail("summary resource counts do not match the approved contract.")
    for key, message in (
        ("destructive_resources", "delete actions are not allowed."),
        ("replacement_resources", "replacement actions are not allowed."),
        ("public_exposure_findings", "public exposure findings are not allowed."),
        ("optional_adapter_resources", "optional adapter resource changes are not allowed."),
        ("high_cost_resources", "high-cost resource changes are not allowed."),
    ):
        if summary.get(key):
            fail(message)


def check_blocked_types(actions: list[dict]) -> None:
    for item in actions:
        resource_type = str(item.get("type", ""))
        if resource_type in BLOCKED_TYPES or resource_type.startswith(BLOCKED_TYPE_PREFIXES):
            fail(f"blocked resource type changed: {resource_type}.")


def main() -> int:
    args = parse_args()
    expected_stage = CONTRACTS[args.contract]
    if args.stage != expected_stage:
        fail(f"contract {args.contract!r} requires stage {expected_stage!r}.")
    txt = read_properties(args.summary_txt)
    summary = json.loads(args.summary_json.read_text(encoding="utf-8"))
    actions = summary.get("resource_actions") or []

    if args.contract == "foundation-apply-role-bootstrap":
        check_risk_gates(summary, txt, "foundation", 4, 0)
        actual = {
            item.get("address"): {
                "type": item.get("type"), "actions": item.get("actions"),
                "changed_attribute_paths": item.get("changed_attribute_paths"),
            }
            for item in actions
        }
        expected = {
            address: {"type": resource_type, "actions": ["create"], "changed_attribute_paths": []}
            for address, resource_type in FOUNDATION_RESOURCES.items()
        }
        if actual != expected:
            fail(f"foundation resource_actions must exactly match {expected!r}, got {actual!r}.")
    else:
        if not args.approved_resource or not args.approved_changed_path:
            fail("--approved-resource and --approved-changed-path are required for eks-runtime contract.")
        check_risk_gates(summary, txt, "eks-runtime", 1, 1)
        expected = [{"address": args.approved_resource, "actions": ["update"], "changed_attribute_paths": [args.approved_changed_path]}]
        actual = [{"address": item.get("address"), "actions": item.get("actions"), "changed_attribute_paths": item.get("changed_attribute_paths")} for item in actions]
        if actual != expected:
            fail(f"resource_actions must exactly match {expected!r}, got {actual!r}.")
    check_blocked_types(actions)
    print("approved_terraform_apply_contract=passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
