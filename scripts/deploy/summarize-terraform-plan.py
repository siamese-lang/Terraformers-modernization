#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


HIGH_COST_TYPES = {
    "aws_cloudfront_distribution",
    "aws_db_instance",
    "aws_eks_cluster",
    "aws_eks_node_group",
    "aws_instance",
    "aws_lb",
    "aws_nat_gateway",
    "aws_opensearch_domain",
    "aws_opensearchserverless_collection",
}
OPTIONAL_ADAPTER_PREFIXES = (
    "aws_bedrockagent_",
    "aws_opensearch_",
    "aws_opensearchserverless_",
)
MAX_CHANGED_PATHS_PER_RESOURCE = 100
_MISSING = object()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a sanitized Terraform plan risk summary.")
    parser.add_argument("--plan-json", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--stage", required=True)
    parser.add_argument("--allow-destructive", action="store_true")
    parser.add_argument("--allow-optional-adapters", action="store_true")
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def walk(value: Any, path: tuple[str, ...] = ()) -> Iterable[tuple[tuple[str, ...], Any]]:
    yield path, value
    if isinstance(value, dict):
        for key, child in value.items():
            yield from walk(child, path + (str(key),))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk(child, path + (str(index),))


def public_exposure_findings(resource_type: str, after: Any) -> list[str]:
    findings: list[str] = []
    if not isinstance(after, dict):
        return findings

    if resource_type in {"aws_security_group_rule", "aws_vpc_security_group_ingress_rule"}:
        for path, value in walk(after):
            if isinstance(value, str) and value in {"0.0.0.0/0", "::/0"}:
                findings.append(f"public ingress CIDR at {'.'.join(path)}")

    if resource_type == "aws_lb" and after.get("internal") is False:
        findings.append("internet-facing load balancer")

    if resource_type == "aws_db_instance" and after.get("publicly_accessible") is True:
        findings.append("publicly accessible database")

    if resource_type == "aws_s3_bucket_public_access_block":
        for key in ("block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"):
            if after.get(key) is False:
                findings.append(f"S3 public access control disabled: {key}")

    if resource_type == "aws_eks_cluster":
        for path, value in walk(after):
            if isinstance(value, str) and value in {"0.0.0.0/0", "::/0"}:
                findings.append(f"EKS public endpoint CIDR at {'.'.join(path)}")

    return findings


def child_marker(marker: Any, key: str | int) -> Any:
    if marker is True:
        return True
    if isinstance(marker, dict):
        return marker.get(str(key), marker.get(key, False))
    if isinstance(marker, list) and isinstance(key, int) and key < len(marker):
        return marker[key]
    return False


def render_path(path: tuple[str, ...]) -> str:
    return ".".join(path) if path else "<root>"


def changed_attribute_paths(
    before: Any,
    after: Any,
    before_sensitive: Any = False,
    after_sensitive: Any = False,
    path: tuple[str, ...] = (),
) -> list[str]:
    if before == after:
        return []
    if before_sensitive is True or after_sensitive is True:
        return [render_path(path)]

    if isinstance(before, dict) and isinstance(after, dict):
        paths: list[str] = []
        for key in sorted(set(before) | set(after), key=str):
            child_path = path + (str(key),)
            before_value = before.get(key, _MISSING)
            after_value = after.get(key, _MISSING)
            if before_value is _MISSING or after_value is _MISSING:
                paths.append(render_path(child_path))
                continue
            paths.extend(
                changed_attribute_paths(
                    before_value,
                    after_value,
                    child_marker(before_sensitive, key),
                    child_marker(after_sensitive, key),
                    child_path,
                )
            )
        return paths

    if isinstance(before, list) and isinstance(after, list):
        if len(before) != len(after):
            return [render_path(path)]
        paths: list[str] = []
        for index, (before_value, after_value) in enumerate(zip(before, after)):
            paths.extend(
                changed_attribute_paths(
                    before_value,
                    after_value,
                    child_marker(before_sensitive, index),
                    child_marker(after_sensitive, index),
                    path + (str(index),),
                )
            )
        return paths

    return [render_path(path)]


def sanitized_changed_paths(change: dict[str, Any], actions: list[str]) -> list[str]:
    if actions != ["update"]:
        return []
    paths = sorted(
        set(
            changed_attribute_paths(
                change.get("before"),
                change.get("after"),
                change.get("before_sensitive", False),
                change.get("after_sensitive", False),
            )
        )
    )
    if len(paths) > MAX_CHANGED_PATHS_PER_RESOURCE:
        omitted = len(paths) - MAX_CHANGED_PATHS_PER_RESOURCE
        return paths[:MAX_CHANGED_PATHS_PER_RESOURCE] + [f"<truncated:{omitted}>"]
    return paths


def main() -> int:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    plan = json.loads(args.plan_json.read_text(encoding="utf-8"))

    action_counts: Counter[str] = Counter()
    type_counts: Counter[str] = Counter()
    resources: list[dict[str, Any]] = []
    destructive: list[str] = []
    replacements: list[str] = []
    public_findings: list[str] = []
    optional_adapters: list[str] = []
    high_cost: list[str] = []

    for resource_change in plan.get("resource_changes", []):
        address = str(resource_change.get("address", "unknown"))
        resource_type = str(resource_change.get("type", "unknown"))
        change = resource_change.get("change", {})
        actions = list(change.get("actions", []))
        if actions == ["no-op"]:
            continue
        action_key = "+".join(actions) if actions else "none"
        action_counts[action_key] += 1
        type_counts[resource_type] += 1
        resources.append(
            {
                "address": address,
                "type": resource_type,
                "actions": actions,
                "changed_attribute_paths": sanitized_changed_paths(change, actions),
            }
        )

        if "delete" in actions:
            destructive.append(address)
        if "delete" in actions and "create" in actions:
            replacements.append(address)
        if resource_type in HIGH_COST_TYPES:
            high_cost.append(address)
        if resource_type.startswith(OPTIONAL_ADAPTER_PREFIXES) and not (args.stage == "rag-runtime" and resource_type.startswith("aws_opensearchserverless_")):
            optional_adapters.append(address)

        after = change.get("after")
        for finding in public_exposure_findings(resource_type, after):
            public_findings.append(f"{address}: {finding}")

    resources.sort(key=lambda item: item["address"])
    update_resources = [item for item in resources if item["actions"] == ["update"]]
    summary = {
        "stage": args.stage,
        "format_version": plan.get("format_version"),
        "terraform_version": plan.get("terraform_version"),
        "resource_change_count": len(resources),
        "update_resource_count": len(update_resources),
        "action_counts": dict(sorted(action_counts.items())),
        "resource_type_counts": dict(sorted(type_counts.items())),
        "resource_actions": resources,
        "destructive_resources": sorted(destructive),
        "replacement_resources": sorted(replacements),
        "public_exposure_findings": sorted(public_findings),
        "optional_adapter_resources": sorted(optional_adapters),
        "high_cost_resources": sorted(high_cost),
        "plan_json_sha256": sha256(args.plan_json),
        "raw_plan_uploaded": False,
        "changed_values_uploaded": False,
    }
    (args.output_dir / "plan-risk-summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    markdown = [
        "# Terraform Plan Risk Summary",
        "",
        f"- Stage: `{args.stage}`",
        f"- Terraform version: `{plan.get('terraform_version')}`",
        f"- Resource changes: `{len(resources)}`",
        f"- Update resources: `{len(update_resources)}`",
        f"- Destructive resources: `{len(destructive)}`",
        f"- Replacement resources: `{len(replacements)}`",
        f"- Public exposure findings: `{len(public_findings)}`",
        f"- Optional adapter resources: `{len(optional_adapters)}`",
        f"- High-cost resource references: `{len(high_cost)}`",
        "- Raw plan JSON, binary plan, and changed attribute values are intentionally not uploaded because they may contain sensitive values.",
        "",
        "## Resource actions",
        "",
        "| Address | Type | Actions | Changed attribute paths |",
        "|---|---|---|---|",
    ]
    for item in resources:
        changed_paths = "<br>".join(f"`{path}`" for path in item["changed_attribute_paths"]) or "-"
        markdown.append(
            f"| `{item['address']}` | `{item['type']}` | `{','.join(item['actions']) or 'none'}` | {changed_paths} |"
        )
    for title, values in (
        ("Destructive or replacement resources", sorted(destructive)),
        ("Public exposure findings", sorted(public_findings)),
        ("Optional adapter resources", sorted(optional_adapters)),
        ("High-cost resource references", sorted(high_cost)),
    ):
        markdown.extend(["", f"## {title}", ""])
        markdown.extend([f"- `{value}`" for value in values] or ["- None"])
    (args.output_dir / "plan-risk-summary.md").write_text("\n".join(markdown) + "\n", encoding="utf-8")

    status = "passed"
    reasons: list[str] = []
    if public_findings:
        status = "failed"
        reasons.append("public-exposure")
    if destructive and not args.allow_destructive:
        status = "failed"
        reasons.append("destructive-action")
    if optional_adapters and not args.allow_optional_adapters:
        status = "failed"
        reasons.append("optional-adapter")

    lines = [
        f"terraform_plan_risk_gate={status}",
        f"plan_stage={args.stage}",
        f"resource_change_count={len(resources)}",
        f"update_resource_count={len(update_resources)}",
        f"destructive_resource_count={len(destructive)}",
        f"replacement_resource_count={len(replacements)}",
        f"public_exposure_finding_count={len(public_findings)}",
        f"optional_adapter_resource_count={len(optional_adapters)}",
        f"high_cost_resource_count={len(high_cost)}",
        "raw_plan_uploaded=false",
        "changed_values_uploaded=false",
        "failure_reasons=" + ",".join(reasons),
    ]
    (args.output_dir / "plan-risk-summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return 0 if status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
