#!/usr/bin/env python3
"""Runtime teardown entrypoint with a bounded Kubernetes-owner recovery hook."""

from __future__ import annotations

import pathlib
import subprocess
from typing import Any

import runtime_teardown_base as base

_original_resolve = base.cmd_resolve
_original_verify_empty_states = base.cmd_verify_empty_states


def cmd_resolve(args: Any) -> None:
    original_writer = base.write_github_output

    def recovery_writer(path: pathlib.Path, values: dict[str, Any]) -> None:
        rendered = dict(values)
        if (
            args.stage == "kubernetes-owners"
            and base.runtime_teardown_execution_context()
        ):
            rendered["kind"] = "kubernetes-recovery"
        original_writer(path, rendered)

    base.write_github_output = recovery_writer
    try:
        _original_resolve(args)
    finally:
        base.write_github_output = original_writer


def cmd_verify_empty_states(args: Any) -> None:
    _original_verify_empty_states(args)
    if not args.output:
        return

    output_path = pathlib.Path(args.output)
    base.normalize_runtime_evidence_names(output_path.parent)

    if (
        args.stage == "kubernetes-owners"
        and base.runtime_teardown_execution_context()
    ):
        script = pathlib.Path(__file__).with_name("recover_kubernetes_owners.sh")
        subprocess.run(
            ["bash", str(script), str(output_path.parent)],
            check=True,
        )


base.cmd_resolve = cmd_resolve
base.cmd_verify_empty_states = cmd_verify_empty_states


if __name__ == "__main__":
    raise SystemExit(base.main())
