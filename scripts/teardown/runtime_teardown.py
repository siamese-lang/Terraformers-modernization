#!/usr/bin/env python3
"""Runtime teardown configuration, plan, state, and static safety checks."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Any


def load_json(path: str | pathlib.Path) -> dict[str, Any]:
    with pathlib.Path(path).open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return value


def stage_config(config: dict[str, Any], stage_name: str) -> dict[str, Any]:
    stages = config.get("stages")
    if not isinstance(stages, dict) or stage_name not in stages:
        raise ValueError(f"Unsupported teardown stage: {stage_name}")
    stage = stages[stage_name]
    if not isinstance(stage, dict):
        raise ValueError(f"Invalid stage configuration: {stage_name}")
    return stage


def confirmation_for(stage_name: str, reviewed_count: int) -> str:
    normalized = re.sub(r"[^A-Z0-9]+", "_", stage_name.upper()).strip("_")
    return f"DESTROY_REVIEWED_{normalized}_{reviewed_count}"


def write_github_output(path: pathlib.Path, values: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        for key, value in values.items():
            if isinstance(value, bool):
                rendered = "true" if value else "false"
            elif isinstance(value, list):
                rendered = ",".join(str(item) for item in value)
            else:
                rendered = str(value)
            if "\n" in rendered or "\r" in rendered:
                raise ValueError(f"Multiline GitHub output is not allowed: {key}")
            handle.write(f"{key}={rendered}\n")


def cmd_resolve(args: argparse.Namespace) -> None:
    config = load_json(args.config)
    if config.get("foundation_excluded") is not True:
        raise ValueError("foundation_excluded must be true")
    stage = stage_config(config, args.stage)
    reviewed_count = int(stage.get("reviewed_delete_count", -1))
    if reviewed_count != args.expected_delete_count:
        raise ValueError(
            "expected_delete_count does not match the reviewed stage contract: "
            f"expected {reviewed_count}, received {args.expected_delete_count}"
        )
    expected_confirmation = confirmation_for(args.stage, reviewed_count)
    if args.confirmation != expected_confirmation:
        raise ValueError(
            "approval_confirmation does not match the exact stage contract: "
            f"expected {expected_confirmation}"
        )

    write_github_output(
        pathlib.Path(args.github_output),
        {
            "stage": args.stage,
            "kind": stage["kind"],
            "order": stage["order"],
            "reviewed_delete_count": reviewed_count,
            "confirmation_expected": expected_confirmation,
            "required_empty_states": stage.get("required_empty_states", []),
            "state_component": stage.get("state_component", ""),
            "terraform_dir": stage.get("terraform_dir", ""),
            "tfvars_secret": stage.get("tfvars_secret", ""),
            "runner_override": stage.get("runner_override", "none"),
        },
    )


def raw_managed_instance_count(raw_state: dict[str, Any]) -> int:
    count = 0
    for resource in raw_state.get("resources", []) or []:
        if not isinstance(resource, dict):
            continue
        if resource.get("mode", "managed") != "managed":
            continue
        count += len(resource.get("instances", []) or [])
    return count


def cmd_managed_count(args: argparse.Namespace) -> None:
    count = raw_managed_instance_count(load_json(args.state_json))
    if args.output:
        pathlib.Path(args.output).write_text(f"{count}\n", encoding="utf-8")
    print(count)


def cmd_verify_empty_states(args: argparse.Namespace) -> None:
    config = load_json(args.config)
    stage = stage_config(config, args.stage)
    state_dir = pathlib.Path(args.state_dir)
    failures: list[str] = []
    result: dict[str, int] = {}
    for component in stage.get("required_empty_states", []):
        path = state_dir / f"{component}.json"
        if not path.exists():
            failures.append(f"missing-state:{component}")
            continue
        count = raw_managed_instance_count(load_json(path))
        result[component] = count
        if count != 0:
            failures.append(f"nonempty-state:{component}:{count}")
    if args.output:
        pathlib.Path(args.output).write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    if failures:
        raise ValueError("Prior teardown states are not empty: " + ", ".join(failures))


def cmd_verify_plan(args: argparse.Namespace) -> None:
    config = load_json(args.config)
    stage = stage_config(config, args.stage)
    if stage.get("kind") != "terraform":
        raise ValueError("Plan verification requires a Terraform stage")
    summary = load_json(args.summary_json)
    if summary.get("destroy_only_contract") != "passed":
        raise ValueError("destroy_only_contract did not pass")
    if int(summary.get("update_resource_count", -1)) != 0:
        raise ValueError("Destroy plan contains managed updates")
    if summary.get("replacement_resources"):
        raise ValueError("Destroy plan contains replacements")
    if summary.get("managed_non_delete_actions"):
        raise ValueError("Destroy plan contains non-delete managed actions")
    if summary.get("data_source_non_read_actions"):
        raise ValueError("Destroy plan contains non-read data-source actions")

    allowed = set(stage.get("allowed_addresses", []))
    actual: set[str] = set()
    for action in summary.get("resource_actions", []):
        if action.get("mode") != "managed":
            continue
        if action.get("actions") != ["delete"]:
            raise ValueError(f"Unexpected managed action: {action}")
        address = action.get("address")
        if not isinstance(address, str):
            raise ValueError("Plan action has no address")
        actual.add(address)

    unexpected = sorted(actual - allowed)
    if unexpected:
        raise ValueError("Destroy plan contains unreviewed addresses: " + ", ".join(unexpected))
    reviewed_count = int(stage["reviewed_delete_count"])
    if len(actual) > reviewed_count:
        raise ValueError(f"Destroy plan exceeds reviewed count: {len(actual)} > {reviewed_count}")
    if int(summary.get("delete_resource_count", -1)) != len(actual):
        raise ValueError("Summary delete count does not match managed delete addresses")

    pathlib.Path(args.output).write_text(
        json.dumps(
            {
                "stage": args.stage,
                "reviewed_delete_count": reviewed_count,
                "actual_delete_count": len(actual),
                "state_aware_subset": actual != allowed,
                "unexpected_addresses": unexpected,
                "contract": "passed",
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def cmd_static_check(args: argparse.Namespace) -> None:
    config = load_json(args.config)
    if config.get("schema_version") != 1:
        raise ValueError("Unsupported teardown config schema")
    if config.get("foundation_excluded") is not True:
        raise ValueError("Runtime teardown must exclude foundation")
    stages = config.get("stages")
    if not isinstance(stages, dict) or not stages:
        raise ValueError("No runtime teardown stages configured")
    if "foundation" in stages:
        raise ValueError("Foundation must not be a runtime teardown stage")

    orders: list[int] = []
    for name, stage in stages.items():
        kind = stage.get("kind")
        if kind not in {"terraform", "kubernetes"}:
            raise ValueError(f"Unsupported stage kind for {name}: {kind}")
        orders.append(int(stage["order"]))
        reviewed = int(stage.get("reviewed_delete_count", -1))
        allowed = stage.get("allowed_addresses", [])
        if kind == "terraform":
            if reviewed <= 0 or len(allowed) != reviewed:
                raise ValueError(
                    f"Reviewed count/address mismatch for {name}: {reviewed} vs {len(allowed)}"
                )
            for key in ("state_component", "terraform_dir", "tfvars_secret", "runner_override"):
                if not stage.get(key):
                    raise ValueError(f"Missing {key} for {name}")
        elif reviewed != 0 or allowed:
            raise ValueError(f"Kubernetes stage must not define Terraform deletes: {name}")
    if sorted(orders) != list(range(1, len(orders) + 1)):
        raise ValueError("Stage order must be contiguous and unique")

    workflow = pathlib.Path(args.workflow).read_text(encoding="utf-8")
    required_fragments = [
        "environment: aws-live-teardown",
        "group: aws-runtime-teardown",
        'terraform -chdir="${TF_DIR}" apply',
        '"${RUNNER_TEMP}/destroy.tfplan"',
        "runtime_teardown.py verify-plan",
        "DESTROY_REVIEWED_",
        "foundation_deleted=false",
        "kubernetes-owners.json",
    ]
    for fragment in required_fragments:
        if fragment not in workflow:
            raise ValueError(f"Workflow is missing required safety fragment: {fragment}")
    for fragment in (
        "terraform destroy",
        "destroy_stage=foundation",
        "aws-live-apply",
        "aws-live-plan",
        "AdministratorAccess",
    ):
        if fragment in workflow:
            raise ValueError(f"Workflow contains forbidden fragment: {fragment}")

    print("runtime_teardown_static_contract=passed")
    print(f"runtime_teardown_stage_count={len(stages)}")
    print("foundation_excluded=true")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    resolve = subparsers.add_parser("resolve")
    resolve.add_argument("--config", required=True)
    resolve.add_argument("--stage", required=True)
    resolve.add_argument("--expected-delete-count", required=True, type=int)
    resolve.add_argument("--confirmation", required=True)
    resolve.add_argument("--github-output", required=True)
    resolve.set_defaults(func=cmd_resolve)

    count = subparsers.add_parser("managed-count")
    count.add_argument("--state-json", required=True)
    count.add_argument("--output")
    count.set_defaults(func=cmd_managed_count)

    empty = subparsers.add_parser("verify-empty-states")
    empty.add_argument("--config", required=True)
    empty.add_argument("--stage", required=True)
    empty.add_argument("--state-dir", required=True)
    empty.add_argument("--output")
    empty.set_defaults(func=cmd_verify_empty_states)

    plan = subparsers.add_parser("verify-plan")
    plan.add_argument("--config", required=True)
    plan.add_argument("--stage", required=True)
    plan.add_argument("--summary-json", required=True)
    plan.add_argument("--output", required=True)
    plan.set_defaults(func=cmd_verify_plan)

    static = subparsers.add_parser("static-check")
    static.add_argument("--config", required=True)
    static.add_argument("--workflow", required=True)
    static.set_defaults(func=cmd_static_check)

    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        args.func(args)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"runtime_teardown_error={exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
