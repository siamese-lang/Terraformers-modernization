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
            if value in {"0.0.0.0/0", "::/0"}:
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
            if value in {"0.0.0.0/0", "::/0"}:
                findings.append(f"EKS public endpoint CIDR at {'.'.join(path)}")

    return findings


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

    for change in plan.get("resource_changes", []):
        address = str(change.get("address", "unknown"))
        resource_type = str(change.get("type", "unknown"))
        actions = list(change.get("change", {}).get("actions", []))
        if actions == ["no-op"]:
            continue
        action_key = "+".join(actions) if actions else "none"
        action_counts[action_key] += 1
        type_counts[resource_type] += 1
        resources.append({"address": address, "type": resource_type, "actions": actions})

        if "delete" in actions:
            destructive.append(address)
        if "delete" in actions and "create" in actions:
            replacements.append(address)
        if resource_type in HIGH_COST_TYPES:
            high_cost.append(address)
        if resource_type.startswith(OPTIONAL_ADAPTER_PREFIXES):
            optional_adapters.append(address)

        after = change.get("change", {}).get("after")
        for finding in public_exposure_findings(resource_type, after):
            public_findings.append(f"{address}: {finding}")

    resources.sort(key=lambda item: item["address"])
    summary = {
        "stage": args.stage,
        "format_version": plan.get("format_version"),
        "terraform_version": plan.get("terraform_version"),
        "resource_change_count": len(resources),
        "action_counts": dict(sorted(action_counts.items())),
        "resource_type_counts": dict(sorted(type_counts.items())),
        "destructive_resources": sorted(destructive),
        "replacement_resources": sorted(replacements),
        "public_exposure_findings": sorted(public_findings),
        "optional_adapter_resources": sorted(optional_adapters),
        "high_cost_resources": sorted(high_cost),
        "plan_json_sha256": sha256(args.plan_json),
        "raw_plan_uploaded": False,
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
        f"- Destructive resources: `{len(destructive)}`",
        f"- Replacement resources: `{len(replacements)}`",
        f"- Public exposure findings: `{len(public_findings)}`",
        f"- Optional adapter resources: `{len(optional_adapters)}`",
        f"- High-cost resource references: `{len(high_cost)}`",
        "- Raw plan JSON and binary plan are intentionally not uploaded because they may contain sensitive values.",
        "",
        "## Resource actions",
        "",
        "| Address | Type | Actions |",
        "|---|---|---|",
    ]
    for item in resources:
        markdown.append(
            f"| `{item['address']}` | `{item['type']}` | `{','.join(item['actions']) or 'none'}` |"
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
        f"destructive_resource_count={len(destructive)}",
        f"replacement_resource_count={len(replacements)}",
        f"public_exposure_finding_count={len(public_findings)}",
        f"optional_adapter_resource_count={len(optional_adapters)}",
        f"high_cost_resource_count={len(high_cost)}",
        "raw_plan_uploaded=false",
        "failure_reasons=" + ",".join(reasons),
    ]
    (args.output_dir / "plan-risk-summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return 0 if status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
