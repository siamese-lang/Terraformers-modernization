#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

REQUIRED_TXT_VALUES = {
    "terraform_plan_risk_gate": "passed",
    "resource_change_count": "1",
    "update_resource_count": "1",
    "destructive_resource_count": "0",
    "replacement_resource_count": "0",
    "public_exposure_finding_count": "0",
    "optional_adapter_resource_count": "0",
    "high_cost_resource_count": "0",
}
BLOCKED_TYPE_PREFIXES = ("aws_security_group", "aws_vpc_security_group_")
BLOCKED_TYPES = {"aws_eks_cluster", "aws_eks_node_group"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify the exact approved Terraform apply contract.")
    parser.add_argument("--summary-json", required=True, type=Path)
    parser.add_argument("--summary-txt", required=True, type=Path)
    parser.add_argument("--stage", required=True)
    parser.add_argument("--approved-resource", required=True)
    parser.add_argument("--approved-changed-path", required=True)
    return parser.parse_args()


def read_properties(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def main() -> int:
    args = parse_args()
    txt = read_properties(args.summary_txt)
    summary = json.loads(args.summary_json.read_text(encoding="utf-8"))

    required_values = dict(REQUIRED_TXT_VALUES)
    required_values["plan_stage"] = args.stage
    for key, expected in required_values.items():
        actual = txt.get(key)
        if actual != expected:
            fail(f"{key} must be {expected!r}, got {actual!r}.")

    if summary.get("stage") != args.stage:
        fail(f"summary stage must be {args.stage!r}.")
    if summary.get("resource_change_count") != 1:
        fail("the full plan must contain exactly one changed resource.")
    if summary.get("update_resource_count") != 1:
        fail("the full plan must contain exactly one in-place update.")
    if summary.get("destructive_resources"):
        fail("delete actions are not allowed.")
    if summary.get("replacement_resources"):
        fail("replacement actions are not allowed.")
    if summary.get("public_exposure_findings"):
        fail("public exposure findings are not allowed.")
    if summary.get("optional_adapter_resources"):
        fail("optional adapter resource changes are not allowed.")
    if summary.get("high_cost_resources"):
        fail("high-cost resource changes are not allowed.")

    resource_actions = summary.get("resource_actions")
    expected_actions = [
        {
            "address": args.approved_resource,
            "actions": ["update"],
            "changed_attribute_paths": [args.approved_changed_path],
        }
    ]
    comparable_actions = [
        {
            "address": item.get("address"),
            "actions": item.get("actions"),
            "changed_attribute_paths": item.get("changed_attribute_paths"),
        }
        for item in resource_actions or []
    ]
    if comparable_actions != expected_actions:
        fail(f"resource_actions must exactly match {expected_actions!r}, got {comparable_actions!r}.")

    for item in resource_actions:
        resource_type = str(item.get("type", ""))
        if resource_type in BLOCKED_TYPES or resource_type.startswith(BLOCKED_TYPE_PREFIXES):
            fail(f"blocked resource type changed: {resource_type}.")

    print("approved_terraform_apply_contract=passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
