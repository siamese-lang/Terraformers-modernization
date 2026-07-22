#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a reviewable live AWS deployment execution plan without contacting AWS."
    )
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    return parser.parse_args()


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("schema_version") != 1:
        raise ValueError("Unsupported live deployment manifest schema_version")
    stages = data.get("stages")
    if not isinstance(stages, list) or not stages:
        raise ValueError("Manifest must contain a non-empty stages list")
    return data


def validate_and_sort(stages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_id: dict[str, dict[str, Any]] = {}
    for stage in stages:
        stage_id = stage.get("id")
        if not isinstance(stage_id, str) or not stage_id:
            raise ValueError("Every stage requires a non-empty id")
        if stage_id in by_id:
            raise ValueError(f"Duplicate stage id: {stage_id}")
        by_id[stage_id] = stage

    incoming = {stage_id: 0 for stage_id in by_id}
    outgoing: dict[str, list[str]] = {stage_id: [] for stage_id in by_id}
    for stage_id, stage in by_id.items():
        dependencies = stage.get("depends_on", [])
        if not isinstance(dependencies, list):
            raise ValueError(f"depends_on must be a list: {stage_id}")
        for dependency in dependencies:
            if dependency not in by_id:
                raise ValueError(f"Unknown dependency {dependency!r} referenced by {stage_id}")
            incoming[stage_id] += 1
            outgoing[dependency].append(stage_id)

    ready = deque(sorted(stage_id for stage_id, count in incoming.items() if count == 0))
    ordered_ids: list[str] = []
    while ready:
        stage_id = ready.popleft()
        ordered_ids.append(stage_id)
        for child in sorted(outgoing[stage_id]):
            incoming[child] -= 1
            if incoming[child] == 0:
                ready.append(child)

    if len(ordered_ids) != len(by_id):
        raise ValueError("Stage dependency graph contains a cycle")
    return [by_id[stage_id] for stage_id in ordered_ids]


def bullet_lines(values: list[str]) -> list[str]:
    return [f"- {value}" for value in values] or ["- None"]


def main() -> int:
    args = parse_args()
    manifest = load_manifest(args.manifest)
    stages = validate_and_sort(manifest["stages"])
    args.output_dir.mkdir(parents=True, exist_ok=True)

    terraform_stages = [stage for stage in stages if stage.get("kind") == "terraform-plan"]
    mutation_stages = [stage for stage in stages if stage.get("mutation_allowed")]
    approval_stages = [stage for stage in stages if stage.get("approval_required")]

    stage_order = "\n".join(stage["id"] for stage in stages) + "\n"
    (args.output_dir / "stage-order.txt").write_text(stage_order, encoding="utf-8")

    approval_gates = {
        "schema_version": 1,
        "public_entrypoint": manifest.get("public_entrypoint"),
        "terraform_plan_stages": [stage.get("plan_stage") for stage in terraform_stages],
        "mutation_stages": [stage["id"] for stage in mutation_stages],
        "approval_required_stages": [stage["id"] for stage in approval_stages],
        "global_stop_conditions": [
            "unexpected AWS account or region",
            "Terraform plan includes delete or replace action",
            "public ingress or public load balancer is introduced",
            "optional production adapters appear without a separate reviewed activation change",
            "credential or Secret value appears in evidence",
            "rollback target or cleanup scope is unknown"
        ]
    }
    (args.output_dir / "approval-gates.json").write_text(
        json.dumps(approval_gates, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    plan_lines = [
        "# Terraformers Live AWS Deployment Execution Plan",
        "",
        f"- Project: `{manifest.get('project')}`",
        f"- Environment: `{manifest.get('environment')}`",
        f"- Public entry point: `{manifest.get('public_entrypoint')}`",
        "- This generated plan performs no AWS authentication, Terraform apply/destroy, Helm install, kubectl apply, image push, S3 sync, or CloudFront invalidation.",
        "",
        "## Stage sequence",
        "",
    ]
    for index, stage in enumerate(stages, start=1):
        plan_lines.extend(
            [
                f"### {index}. `{stage['id']}`",
                "",
                f"- Kind: `{stage.get('kind')}`",
                f"- Dependencies: {', '.join(f'`{item}`' for item in stage.get('depends_on', [])) or 'None'}",
                f"- Mutation allowed in this stage definition: `{str(bool(stage.get('mutation_allowed'))).lower()}`",
                f"- Explicit approval required: `{str(bool(stage.get('approval_required'))).lower()}`",
            ]
        )
        if stage.get("terraform_directory"):
            plan_lines.append(f"- Terraform directory: `{stage['terraform_directory']}`")
        if stage.get("plan_stage"):
            plan_lines.append(f"- Guarded plan workflow selector: `{stage['plan_stage']}`")
        plan_lines.extend(["", "Success evidence:", *bullet_lines(stage.get("success_evidence", []))])
        plan_lines.extend(["", "Stop conditions:", *bullet_lines(stage.get("stop_conditions", []))])
        plan_lines.extend(["", f"Rollback boundary: {stage.get('rollback', 'Not specified')}", ""])

    (args.output_dir / "execution-plan.md").write_text("\n".join(plan_lines) + "\n", encoding="utf-8")

    rollback_lines = [
        "# Rollback Matrix",
        "",
        "| Stage | Mutation | Approval | Rollback boundary |",
        "|---|---:|---:|---|",
    ]
    for stage in stages:
        rollback = str(stage.get("rollback", "Not specified")).replace("|", "\\|")
        rollback_lines.append(
            f"| `{stage['id']}` | {str(bool(stage.get('mutation_allowed'))).lower()} | "
            f"{str(bool(stage.get('approval_required'))).lower()} | {rollback} |"
        )
    (args.output_dir / "rollback-matrix.md").write_text("\n".join(rollback_lines) + "\n", encoding="utf-8")

    summary = [
        "live_deployment_execution_plan=generated",
        f"stage_count={len(stages)}",
        f"terraform_plan_stage_count={len(terraform_stages)}",
        f"mutation_stage_count={len(mutation_stages)}",
        f"approval_required_stage_count={len(approval_stages)}",
        f"public_entrypoint={manifest.get('public_entrypoint')}",
        "terraform_apply_automated=false",
        "terraform_destroy_automated=false",
        "kubernetes_apply_automated=false",
        "helm_install_automated=false",
        "aws_mutation=none",
    ]
    (args.output_dir / "plan-summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print("\n".join(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
