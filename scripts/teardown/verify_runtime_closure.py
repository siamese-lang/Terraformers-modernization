#!/usr/bin/env python3
"""Read-only verification for completed Terraformers runtime teardown."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
from typing import Any


REGION_DEFAULT = "ap-northeast-2"
RUNTIME_STATES = (
    "frontend-delivery",
    "rag-runtime",
    "eks-runtime",
    "stateful-dependencies",
    "runtime-dependencies",
    "network",
)


def load_json(path: pathlib.Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return value


def managed_count(state: dict[str, Any]) -> int:
    total = 0
    for resource in state.get("resources", []) or []:
        if not isinstance(resource, dict) or resource.get("mode", "managed") != "managed":
            continue
        total += len(resource.get("instances", []) or [])
    return total


def aws(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["aws", *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def aws_json(arguments: list[str], absent_markers: tuple[str, ...] = ()) -> dict[str, Any] | None:
    result = aws([*arguments, "--output", "json"])
    combined = f"{result.stdout}\n{result.stderr}"
    if result.returncode != 0:
        if any(marker in combined for marker in absent_markers):
            return None
        raise ValueError(f"AWS read failed: {' '.join(arguments[:2])}")
    text = result.stdout.strip() or "{}"
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"AWS returned invalid JSON: {' '.join(arguments[:2])}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"AWS returned non-object JSON: {' '.join(arguments[:2])}")
    return value


def head_bucket_absent(bucket: str) -> bool:
    result = aws(["s3api", "head-bucket", "--bucket", bucket])
    if result.returncode == 0:
        return False
    combined = f"{result.stdout}\n{result.stderr}"
    if any(marker in combined for marker in ("404", "Not Found", "NoSuchBucket")):
        return True
    raise ValueError(f"Unable to verify S3 bucket absence: {bucket}")


def queue_absent(name: str, region: str) -> bool:
    result = aws(
        [
            "sqs",
            "get-queue-url",
            "--region",
            region,
            "--queue-name",
            name,
            "--query",
            "QueueUrl",
            "--output",
            "text",
        ]
    )
    if result.returncode == 0:
        return not result.stdout.strip() or result.stdout.strip() == "None"
    combined = f"{result.stdout}\n{result.stderr}"
    if "AWS.SimpleQueueService.NonExistentQueue" in combined or "does not exist" in combined:
        return True
    raise ValueError(f"Unable to verify SQS queue absence: {name}")


def exact_absence_results(account_id: str, region: str) -> tuple[dict[str, Any], list[str]]:
    failures: list[str] = []
    result: dict[str, Any] = {}

    cluster = aws_json(
        ["eks", "describe-cluster", "--region", region, "--name", "terraformers-dev-backend"],
        ("ResourceNotFoundException", "No cluster found"),
    )
    result["eks_cluster_count"] = 0 if cluster is None else 1

    database = aws_json(
        [
            "rds",
            "describe-db-instances",
            "--region",
            region,
            "--db-instance-identifier",
            "terraformers-modernization-dev-mariadb",
        ],
        ("DBInstanceNotFound", "not found"),
    )
    result["rds_instance_count"] = 0 if database is None else len(database.get("DBInstances", []) or [])

    repository = aws_json(
        ["ecr", "describe-repositories", "--region", region, "--repository-names", "terraformers-backend"],
        ("RepositoryNotFoundException", "not found"),
    )
    result["ecr_repository_count"] = 0 if repository is None else len(repository.get("repositories", []) or [])

    bucket_names = (
        f"terraformers-modernization-dev-frontend-{account_id}",
        f"terraformers-dev-rag-corpus-{account_id}",
        f"terraformers-dev-upload-{account_id}",
        f"terraformers-dev-result-{account_id}",
    )
    result["project_bucket_count"] = sum(0 if head_bucket_absent(name) else 1 for name in bucket_names)

    queue_names = ("terraformers-ai-log-live-smoke", "terraformers-terraform-log-live-smoke")
    result["project_queue_count"] = sum(0 if queue_absent(name, region) else 1 for name in queue_names)

    aoss = aws_json(["opensearchserverless", "list-collections", "--region", region]) or {}
    result["aoss_collection_count"] = len(
        [item for item in aoss.get("collectionSummaries", []) or [] if item.get("name") == "terraformers-dev-refs"]
    )

    codebuild = aws_json(
        ["codebuild", "batch-get-projects", "--region", region, "--names", "terraformers-dev-refs-ingestion"]
    ) or {}
    result["codebuild_project_count"] = len(codebuild.get("projects", []) or [])

    pools = aws_json(["cognito-idp", "list-user-pools", "--region", region, "--max-results", "60"]) or {}
    result["project_user_pool_count"] = len(
        [
            pool
            for pool in pools.get("UserPools", []) or []
            if "terraformers-modernization" in str(pool.get("Name", ""))
        ]
    )

    secrets = aws_json(
        ["secretsmanager", "list-secrets", "--region", region, "--include-planned-deletion"]
    ) or {}
    matching_secrets = [
        secret
        for secret in secrets.get("SecretList", []) or []
        if secret.get("Name") == "terraformers/dev/backend/runtime"
    ]
    result["active_runtime_secret_count"] = len(
        [secret for secret in matching_secrets if not secret.get("DeletedDate")]
    )
    result["pending_runtime_secret_deletion_count"] = len(
        [secret for secret in matching_secrets if secret.get("DeletedDate")]
    )

    vpcs = aws_json(
        [
            "ec2",
            "describe-vpcs",
            "--region",
            region,
            "--filters",
            "Name=tag:Name,Values=terraformers-modernization-dev-vpc",
        ]
    ) or {}
    result["exact_runtime_vpc_count"] = len(vpcs.get("Vpcs", []) or [])

    load_balancers = aws_json(["elbv2", "describe-load-balancers", "--region", region]) or {}
    result["project_load_balancer_count"] = len(
        [
            item
            for item in load_balancers.get("LoadBalancers", []) or []
            if "terraformers" in str(item.get("LoadBalancerName", "")).lower()
        ]
    )

    target_groups = aws_json(["elbv2", "describe-target-groups", "--region", region]) or {}
    result["project_target_group_count"] = len(
        [
            item
            for item in target_groups.get("TargetGroups", []) or []
            if "terraformers" in str(item.get("TargetGroupName", "")).lower()
        ]
    )

    origins = aws_json(["cloudfront", "list-vpc-origins"]) or {}
    origin_items = ((origins.get("VpcOriginList") or {}).get("Items") or [])
    result["project_cloudfront_vpc_origin_count"] = len(
        [item for item in origin_items if "terraformers" in str(item.get("Name", "")).lower()]
    )

    distributions = aws_json(["cloudfront", "list-distributions"]) or {}
    distribution_items = ((distributions.get("DistributionList") or {}).get("Items") or [])
    result["project_cloudfront_distribution_count"] = len(
        [
            item
            for item in distribution_items
            if item.get("Comment") == "Terraformers React SPA and same-origin backend API delivery."
        ]
    )

    logs = aws_json(["logs", "describe-log-groups", "--region", region]) or {}
    result["project_log_group_count"] = len(
        [
            item
            for item in logs.get("logGroups", []) or []
            if "terraformers" in str(item.get("logGroupName", "")).lower()
        ]
    )

    hard_zero_fields = (
        "eks_cluster_count",
        "rds_instance_count",
        "ecr_repository_count",
        "project_bucket_count",
        "project_queue_count",
        "aoss_collection_count",
        "codebuild_project_count",
        "project_user_pool_count",
        "active_runtime_secret_count",
        "exact_runtime_vpc_count",
        "project_load_balancer_count",
        "project_target_group_count",
        "project_cloudfront_vpc_origin_count",
        "project_cloudfront_distribution_count",
        "project_log_group_count",
    )
    for field in hard_zero_fields:
        if int(result[field]) != 0:
            failures.append(f"nonzero:{field}:{result[field]}")

    return result, failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--account-id", required=True)
    parser.add_argument("--region", default=REGION_DEFAULT)
    parser.add_argument("--kubernetes-marker", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    if not re.fullmatch(r"[0-9]{12}", args.account_id):
        raise ValueError("Invalid AWS account ID")

    state_dir = pathlib.Path(args.state_dir)
    state_counts: dict[str, int] = {}
    failures: list[str] = []
    for component in RUNTIME_STATES:
        path = state_dir / f"{component}.json"
        if not path.exists():
            failures.append(f"missing-state:{component}")
            continue
        count = managed_count(load_json(path))
        state_counts[component] = count
        if count != 0:
            failures.append(f"nonzero-state:{component}:{count}")

    marker = load_json(pathlib.Path(args.kubernetes_marker))
    owners_removed = marker.get("owners_removed") is True
    if not owners_removed:
        failures.append("kubernetes-owner-marker-not-complete")

    resource_counts, resource_failures = exact_absence_results(args.account_id, args.region)
    failures.extend(resource_failures)

    pending_secret_count = int(resource_counts["pending_runtime_secret_deletion_count"])
    status = "passed" if not failures else "failed"
    if status == "passed" and pending_secret_count:
        status = "passed_with_pending_secret_deletion"

    evidence = {
        "account_id_verified": True,
        "region": args.region,
        "runtime_state_counts": state_counts,
        "kubernetes_owners_removed": owners_removed,
        "resource_counts": resource_counts,
        "pending_secret_deletion_is_active_runtime": False,
        "foundation_checked": False,
        "foundation_deleted": False,
        "failures": failures,
        "contract": status,
    }
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    if failures:
        print("runtime_closure_verification=failed", file=sys.stderr)
        return 1
    print(f"runtime_closure_verification={status}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"runtime_closure_error={exc}", file=sys.stderr)
        raise SystemExit(1)
