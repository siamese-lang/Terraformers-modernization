#!/usr/bin/env python3
"""Runtime teardown entrypoint with bounded recovery hooks."""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import time
from typing import Any

import runtime_teardown_base as base

_original_resolve = base.cmd_resolve
_original_verify_empty_states = base.cmd_verify_empty_states
_original_managed_count = base.cmd_managed_count


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


def _aws(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["aws", *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def _aws_json(
    arguments: list[str],
    *,
    absent_markers: tuple[str, ...] = (),
) -> dict[str, Any] | None:
    completed = _aws([*arguments, "--output", "json"])
    if completed.returncode == 0:
        try:
            value = json.loads(completed.stdout or "{}")
        except json.JSONDecodeError as exc:
            raise ValueError(
                f"AWS command returned invalid JSON: {' '.join(arguments[:2])}"
            ) from exc
        if not isinstance(value, dict):
            raise ValueError(
                f"AWS command returned a non-object: {' '.join(arguments[:2])}"
            )
        return value

    combined = f"{completed.stdout}\n{completed.stderr}"
    if any(marker in combined for marker in absent_markers):
        return None
    raise ValueError(f"AWS command failed: {' '.join(arguments[:2])}")


def _stateful_post_destroy_context(args: Any) -> bool:
    tf_dir = os.environ.get("TF_DIR", "").replace("\\", "/").rstrip("/")
    if not (
        base.runtime_teardown_execution_context()
        and tf_dir.endswith(
            "infra/terraform/envs/backend-stateful-dependencies"
        )
    ):
        return False
    return base.raw_managed_instance_count(base.load_json(args.state_json)) == 0


def _backup_count(region: str, dbi_resource_id: str) -> int:
    response = _aws_json(
        [
            "rds",
            "describe-db-instance-automated-backups",
            "--region",
            region,
            "--dbi-resource-id",
            dbi_resource_id,
        ],
        absent_markers=(
            "DBInstanceAutomatedBackupNotFound",
            "not found",
        ),
    )
    if response is None:
        return 0
    backups = response.get("DBInstanceAutomatedBackups", []) or []
    if not isinstance(backups, list):
        raise ValueError("RDS automated backup response has an invalid shape")
    return len(backups)


def _secret_exists(region: str, secret_arn: str) -> bool:
    response = _aws_json(
        [
            "secretsmanager",
            "describe-secret",
            "--region",
            region,
            "--secret-id",
            secret_arn,
        ],
        absent_markers=("ResourceNotFoundException", "not found"),
    )
    return response is not None


def _project_user_pools(region: str) -> list[str]:
    response = _aws_json(
        [
            "cognito-idp",
            "list-user-pools",
            "--region",
            region,
            "--max-results",
            "60",
        ]
    )
    assert response is not None
    pool_ids: list[str] = []
    for pool in response.get("UserPools", []) or []:
        if not isinstance(pool, dict):
            continue
        name = pool.get("Name")
        pool_id = pool.get("Id")
        if (
            isinstance(name, str)
            and "terraformers-modernization" in name
            and isinstance(pool_id, str)
        ):
            pool_ids.append(pool_id)
    return pool_ids


def _recover_stateful_residuals(output_dir: pathlib.Path) -> None:
    region = os.environ.get("AWS_REGION", "ap-northeast-2")
    runner_temp = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp"))
    identifiers_path = runner_temp / "stateful-identifiers.json"
    identifiers = (
        base.load_json(identifiers_path)
        if identifiers_path.exists()
        else {}
    )

    dbi_resource_id = str(identifiers.get("dbi_resource_id") or "")
    managed_secret_arn = str(identifiers.get("managed_secret_arn") or "")

    initial_backup_count = (
        _backup_count(region, dbi_resource_id)
        if dbi_resource_id
        else 0
    )
    backup_delete_requested = False
    if initial_backup_count > 0:
        completed = _aws(
            [
                "rds",
                "delete-db-instance-automated-backup",
                "--region",
                region,
                "--dbi-resource-id",
                dbi_resource_id,
            ]
        )
        combined = f"{completed.stdout}\n{completed.stderr}"
        if completed.returncode != 0 and not any(
            marker in combined
            for marker in (
                "DBInstanceAutomatedBackupNotFound",
                "not found",
            )
        ):
            raise ValueError(
                "Unable to request retained RDS automated backup deletion"
            )
        backup_delete_requested = completed.returncode == 0

    final_backup_count = initial_backup_count
    backup_attempts = 0
    for backup_attempts in range(1, 41):
        final_backup_count = (
            _backup_count(region, dbi_resource_id)
            if dbi_resource_id
            else 0
        )
        if final_backup_count == 0:
            break
        time.sleep(15)
    if final_backup_count != 0:
        raise ValueError(
            "Retained RDS automated backup did not converge to zero"
        )

    initial_secret_exists = (
        _secret_exists(region, managed_secret_arn)
        if managed_secret_arn
        else False
    )
    final_secret_exists = initial_secret_exists
    secret_attempts = 0
    for secret_attempts in range(1, 41):
        final_secret_exists = (
            _secret_exists(region, managed_secret_arn)
            if managed_secret_arn
            else False
        )
        if not final_secret_exists:
            break
        time.sleep(15)
    if final_secret_exists:
        raise ValueError("RDS managed master secret did not disappear")

    initial_pool_ids = _project_user_pools(region)
    for pool_id in initial_pool_ids:
        completed = _aws(
            [
                "cognito-idp",
                "delete-user-pool",
                "--region",
                region,
                "--user-pool-id",
                pool_id,
            ]
        )
        combined = f"{completed.stdout}\n{completed.stderr}"
        if (
            completed.returncode != 0
            and "ResourceNotFoundException" not in combined
        ):
            raise ValueError(
                "Unable to delete a Terraformers Cognito user pool"
            )

    final_pool_ids = initial_pool_ids
    pool_attempts = 0
    for pool_attempts in range(1, 31):
        final_pool_ids = _project_user_pools(region)
        if not final_pool_ids:
            break
        for pool_id in final_pool_ids:
            _aws(
                [
                    "cognito-idp",
                    "delete-user-pool",
                    "--region",
                    region,
                    "--user-pool-id",
                    pool_id,
                ]
            )
        time.sleep(10)
    if final_pool_ids:
        raise ValueError(
            "Terraformers Cognito user pools did not converge to zero"
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "stateful-residual-convergence.json").write_text(
        json.dumps(
            {
                "stage": "stateful-dependencies",
                "initial_automated_backup_count": initial_backup_count,
                "final_automated_backup_count": final_backup_count,
                "automated_backup_delete_requested": (
                    backup_delete_requested
                ),
                "automated_backup_poll_attempts": backup_attempts,
                "initial_managed_secret_exists": initial_secret_exists,
                "final_managed_secret_exists": final_secret_exists,
                "managed_secret_poll_attempts": secret_attempts,
                "initial_project_user_pool_count": len(initial_pool_ids),
                "final_project_user_pool_count": len(final_pool_ids),
                "user_pool_poll_attempts": pool_attempts,
                "contract": "passed",
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def cmd_managed_count(args: Any) -> None:
    _original_managed_count(args)
    if not _stateful_post_destroy_context(args):
        return
    output_dir = (
        pathlib.Path(args.output).parent
        if args.output
        else pathlib.Path("artifacts/aws-runtime-teardown")
    )
    _recover_stateful_residuals(output_dir)


base.cmd_resolve = cmd_resolve
base.cmd_verify_empty_states = cmd_verify_empty_states
base.cmd_managed_count = cmd_managed_count


if __name__ == "__main__":
    raise SystemExit(base.main())
