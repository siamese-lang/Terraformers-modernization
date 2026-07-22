#!/usr/bin/env python3
"""Runtime teardown entrypoint with bounded recovery hooks."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import time
from typing import Any, Callable

import runtime_teardown_base as base

_original_resolve = base.cmd_resolve
_original_verify_empty_states = base.cmd_verify_empty_states
_original_managed_count = base.cmd_managed_count


def cmd_resolve(args: Any) -> None:
    original_writer = base.write_github_output

    def recovery_writer(path: pathlib.Path, values: dict[str, Any]) -> None:
        rendered = dict(values)
        if args.stage == "kubernetes-owners" and base.runtime_teardown_execution_context():
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
    if args.stage == "kubernetes-owners" and base.runtime_teardown_execution_context():
        script = pathlib.Path(__file__).with_name("recover_kubernetes_owners.sh")
        subprocess.run(["bash", str(script), str(output_path.parent)], check=True)


def _aws(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["aws", *arguments], check=False, capture_output=True, text=True)


def _json(arguments: list[str], absent: tuple[str, ...] = ()) -> dict[str, Any] | None:
    result = _aws([*arguments, "--output", "json"])
    combined = f"{result.stdout}\n{result.stderr}"
    if result.returncode != 0:
        if any(marker in combined for marker in absent):
            return None
        raise ValueError(f"AWS command failed: {' '.join(arguments[:2])}")
    try:
        value = json.loads(result.stdout or "{}")
    except json.JSONDecodeError as exc:
        raise ValueError(f"AWS command returned invalid JSON: {' '.join(arguments[:2])}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"AWS command returned a non-object: {' '.join(arguments[:2])}")
    return value


def _poll(check: Callable[[], bool], attempts: int, delay: int, label: str) -> int:
    for attempt in range(1, attempts + 1):
        if check():
            return attempt
        if attempt < attempts:
            time.sleep(delay)
    raise ValueError(f"{label} did not converge")


def _stateful_context(args: Any) -> bool:
    tf_dir = os.environ.get("TF_DIR", "").replace("\\", "/").rstrip("/")
    return (
        base.runtime_teardown_execution_context()
        and tf_dir.endswith("infra/terraform/envs/backend-stateful-dependencies")
        and base.raw_managed_instance_count(base.load_json(args.state_json)) == 0
    )


def _recover_stateful(output_dir: pathlib.Path) -> None:
    region = os.environ.get("AWS_REGION", "ap-northeast-2")
    identifiers_path = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp")) / "stateful-identifiers.json"
    identifiers = base.load_json(identifiers_path) if identifiers_path.exists() else {}
    dbi_id = str(identifiers.get("dbi_resource_id") or "")
    secret_arn = str(identifiers.get("managed_secret_arn") or "")

    def backup_count() -> int:
        if not dbi_id:
            return 0
        response = _json(
            ["rds", "describe-db-instance-automated-backups", "--region", region, "--dbi-resource-id", dbi_id],
            ("DBInstanceAutomatedBackupNotFound", "not found"),
        )
        return len((response or {}).get("DBInstanceAutomatedBackups", []) or [])

    initial_backups = backup_count()
    backup_delete_requested = False
    if initial_backups:
        result = _aws(["rds", "delete-db-instance-automated-backup", "--region", region, "--dbi-resource-id", dbi_id])
        combined = f"{result.stdout}\n{result.stderr}"
        if result.returncode != 0 and not any(
            marker in combined for marker in ("DBInstanceAutomatedBackupNotFound", "not found")
        ):
            raise ValueError("Unable to request retained RDS automated backup deletion")
        backup_delete_requested = result.returncode == 0
    backup_attempts = _poll(lambda: backup_count() == 0, 40, 15, "RDS automated backup deletion")

    def secret_exists() -> bool:
        if not secret_arn:
            return False
        return _json(
            ["secretsmanager", "describe-secret", "--region", region, "--secret-id", secret_arn],
            ("ResourceNotFoundException", "not found"),
        ) is not None

    initial_secret = secret_exists()
    secret_attempts = _poll(lambda: not secret_exists(), 40, 15, "RDS managed secret deletion")

    def pool_ids() -> list[str]:
        response = _json(["cognito-idp", "list-user-pools", "--region", region, "--max-results", "60"])
        pools = (response or {}).get("UserPools", []) or []
        return [
            str(pool["Id"])
            for pool in pools
            if isinstance(pool, dict)
            and isinstance(pool.get("Name"), str)
            and "terraformers-modernization" in pool["Name"]
            and pool.get("Id")
        ]

    initial_pools = pool_ids()

    def pools_absent() -> bool:
        current = pool_ids()
        for pool_id in current:
            result = _aws(["cognito-idp", "delete-user-pool", "--region", region, "--user-pool-id", pool_id])
            if result.returncode != 0 and "ResourceNotFoundException" not in f"{result.stdout}\n{result.stderr}":
                raise ValueError("Unable to delete a Terraformers Cognito user pool")
        return not current

    pool_attempts = _poll(pools_absent, 30, 10, "Cognito user-pool deletion")
    evidence = {
        "stage": "stateful-dependencies",
        "initial_automated_backup_count": initial_backups,
        "final_automated_backup_count": backup_count(),
        "automated_backup_delete_requested": backup_delete_requested,
        "automated_backup_poll_attempts": backup_attempts,
        "initial_managed_secret_exists": initial_secret,
        "final_managed_secret_exists": secret_exists(),
        "managed_secret_poll_attempts": secret_attempts,
        "initial_project_user_pool_count": len(initial_pools),
        "final_project_user_pool_count": len(pool_ids()),
        "user_pool_poll_attempts": pool_attempts,
        "contract": "passed",
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "stateful-residual-convergence.json").write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def cmd_managed_count(args: Any) -> None:
    _original_managed_count(args)
    if _stateful_context(args):
        output_dir = pathlib.Path(args.output).parent if args.output else pathlib.Path("artifacts/aws-runtime-teardown")
        _recover_stateful(output_dir)


base.cmd_resolve = cmd_resolve
base.cmd_verify_empty_states = cmd_verify_empty_states
base.cmd_managed_count = cmd_managed_count

if __name__ == "__main__":
    raise SystemExit(base.main())
