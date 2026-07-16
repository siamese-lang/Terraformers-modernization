#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


def run(*args: str) -> tuple[int, str, str]:
    result = subprocess.run(args, text=True, capture_output=True, check=False)
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def json_command(*args: str) -> tuple[int, Any]:
    code, stdout, _ = run(*args)
    if code != 0:
        return code, {}
    try:
        return 0, json.loads(stdout)
    except json.JSONDecodeError:
        return 1, {}


def named_blocks(text: str, kind: str) -> dict[str, str]:
    pattern = re.compile(rf'(?m)^\s*{kind}\s+"([^"]+)"\s*\{{')
    blocks: dict[str, str] = {}
    for match in pattern.finditer(text):
        depth = 0
        quoted = False
        escaped = False
        end = None
        for index in range(match.end() - 1, len(text)):
            char = text[index]
            if quoted:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    quoted = False
                continue
            if char == '"':
                quoted = True
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end is None:
            raise ValueError(f"Unclosed {kind} block: {match.group(1)}")
        blocks[match.group(1)] = text[match.start():end]
    return blocks


def variable_contract(path: Path) -> tuple[list[str], list[str]]:
    blocks = named_blocks(path.read_text(encoding="utf-8"), "variable")
    all_names = list(blocks)
    required = [name for name, block in blocks.items() if not re.search(r"\bdefault\s*=", block)]
    return all_names, required


def output_names(path: Path) -> set[str]:
    return set(named_blocks(path.read_text(encoding="utf-8"), "output"))


def names(payload: Any, key: str) -> set[str]:
    values = payload.get(key, []) if isinstance(payload, dict) else []
    return {str(item.get("name")) for item in values if isinstance(item, dict) and item.get("name")}


def variable_values(payload: Any) -> dict[str, str]:
    values = payload.get("variables", []) if isinstance(payload, dict) else []
    return {
        str(item.get("name")): str(item.get("value", ""))
        for item in values
        if isinstance(item, dict) and item.get("name")
    }


def mask_account(value: str) -> str:
    return f"{value[:4]}****{value[-4:]}" if len(value) >= 8 else "***"


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only inventory of live AWS deployment prerequisites.")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--repo", default="siamese-lang/Terraformers-modernization")
    parser.add_argument("--branch", default="agent/rdb-domain-realignment")
    parser.add_argument("--contract", default="config/live-aws-prerequisites.json")
    parser.add_argument("--output-dir", default="artifacts/live-aws-prerequisite-inventory")
    parser.add_argument("--expected-account-id", default="")
    parser.add_argument("--static-only", action="store_true")
    parser.add_argument("--skip-aws", action="store_true")
    parser.add_argument("--fail-on-missing", action="store_true")
    args = parser.parse_args()

    root = Path(args.repo_root).resolve()
    contract = json.loads((root / args.contract).read_text(encoding="utf-8"))
    output_dir = root / args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []
    stages = {stage["id"]: stage for stage in contract["terraform_stages"]}
    stage_report: list[dict[str, Any]] = []

    for stage in contract["terraform_stages"]:
        stage_dir = root / stage["directory"]
        variables_path = stage_dir / "variables.tf"
        if not variables_path.is_file():
            errors.append(f"missing-variables-file:{stage['id']}")
            continue
        all_variables, required = variable_contract(variables_path)
        if required != stage["required_variables"]:
            errors.append(f"required-variable-drift:{stage['id']}:expected={stage['required_variables']}:actual={required}")
        unknown_operator = sorted(set(stage.get("operator_inputs", [])) - set(all_variables))
        if unknown_operator:
            errors.append(f"unknown-operator-input:{stage['id']}:{','.join(unknown_operator)}")
        sources: list[dict[str, str]] = []
        for variable_name, source in stage.get("input_sources", {}).items():
            if variable_name not in all_variables:
                errors.append(f"source-target-variable-missing:{stage['id']}:{variable_name}")
                continue
            source_stage_id, source_output = source.split(".", 1)
            if source_stage_id == "live-private-origin":
                sources.append({"variable": variable_name, "source": source, "status": "live-handoff"})
                continue
            source_stage = stages.get(source_stage_id)
            outputs_path = root / source_stage["directory"] / "outputs.tf" if source_stage else Path()
            present = bool(source_stage and outputs_path.is_file() and source_output in output_names(outputs_path))
            sources.append({"variable": variable_name, "source": source, "status": "present" if present else "missing"})
            if not present:
                errors.append(f"source-output-missing:{stage['id']}:{source}")
        stage_report.append({
            "id": stage["id"],
            "required_variables": required,
            "operator_inputs": stage.get("operator_inputs", []),
            "sources": sources,
            "live_prerequisite": stage["live_prerequisite"],
        })

    static_errors = [error for error in errors if error.startswith((
        "missing-variables-file:", "required-variable-drift:", "unknown-operator-input:",
        "source-target-variable-missing:", "source-output-missing:",
    ))]
    static_ok = not static_errors
    github_report: dict[str, Any] = {"status": "skipped-static-only"}
    aws_report: dict[str, Any] = {"status": "skipped-static-only"}
    missing_variables: list[str] = []
    missing_secrets: list[str] = []

    if not args.static_only:
        environment = contract["github_environment"]
        if not shutil.which("gh"):
            errors.append("command-missing:gh")
            github_report = {"status": "gh-not-found"}
        elif run("gh", "auth", "status", "--hostname", "github.com")[0] != 0:
            errors.append("github-auth-unavailable")
            github_report = {"status": "auth-failed"}
        else:
            env_code, _ = json_command("gh", "api", f"repos/{args.repo}/environments/{environment}")
            env_exists = env_code == 0
            if not env_exists:
                errors.append(f"github-environment-missing:{environment}")
            _, repo_vars = json_command("gh", "api", f"repos/{args.repo}/actions/variables")
            _, repo_secrets = json_command("gh", "api", f"repos/{args.repo}/actions/secrets")
            env_vars: Any = {}
            env_secrets: Any = {}
            if env_exists:
                _, env_vars = json_command("gh", "api", f"repos/{args.repo}/environments/{environment}/variables")
                _, env_secrets = json_command("gh", "api", f"repos/{args.repo}/environments/{environment}/secrets")
            merged_values = variable_values(repo_vars)
            merged_values.update(variable_values(env_vars))
            variable_name_set = set(merged_values)
            secret_name_set = names(repo_secrets, "secrets") | names(env_secrets, "secrets")
            missing_variables = [name for name in contract["required_github_variables"] if name not in variable_name_set]
            missing_secrets = [name for name in contract["required_github_secrets"] if name not in secret_name_set]
            errors.extend(f"github-variable-missing:{name}" for name in missing_variables)
            errors.extend(f"github-secret-missing:{name}" for name in missing_secrets)
            github_report = {
                "status": "ready" if env_exists and not missing_variables and not missing_secrets else "incomplete",
                "environment": environment,
                "environment_exists": env_exists,
                "missing_variables": missing_variables,
                "missing_secrets": missing_secrets,
                "secret_values_read": False,
            }

            if args.skip_aws:
                aws_report = {"status": "skipped-by-request"}
            elif not shutil.which("aws"):
                errors.append("command-missing:aws")
                aws_report = {"status": "aws-not-found"}
            else:
                identity_code, identity = json_command("aws", "sts", "get-caller-identity", "--output", "json")
                if identity_code != 0:
                    errors.append("aws-identity-unavailable")
                    aws_report = {"status": "identity-failed"}
                else:
                    account = str(identity.get("Account", ""))
                    expected = args.expected_account_id or account
                    account_matches = account == expected
                    if not account_matches:
                        errors.append("aws-account-mismatch")
                    region = merged_values.get("AWS_REGION", "ap-northeast-2")
                    bucket = merged_values.get("AWS_TERRAFORM_STATE_BUCKET", "")
                    table = merged_values.get("AWS_TERRAFORM_LOCK_TABLE", "")
                    bucket_access = bool(bucket and run("aws", "s3api", "head-bucket", "--bucket", bucket)[0] == 0)
                    versioning = "unresolved"
                    if bucket_access:
                        _, version_payload = json_command("aws", "s3api", "get-bucket-versioning", "--bucket", bucket, "--output", "json")
                        versioning = str(version_payload.get("Status", "NotEnabled"))
                    if not bucket_access:
                        errors.append("state-bucket-inaccessible")
                    elif versioning != "Enabled":
                        errors.append("state-bucket-versioning-not-enabled")
                    table_status = "unresolved"
                    if table:
                        table_code, table_payload = json_command("aws", "dynamodb", "describe-table", "--table-name", table, "--region", region, "--output", "json")
                        if table_code == 0:
                            table_status = str(table_payload.get("Table", {}).get("TableStatus", ""))
                    if table_status != "ACTIVE":
                        errors.append("state-lock-table-not-active")
                    aws_report = {
                        "status": "ready" if account_matches and bucket_access and versioning == "Enabled" and table_status == "ACTIVE" else "incomplete",
                        "caller_account": mask_account(account),
                        "expected_account": mask_account(expected),
                        "account_matches": account_matches,
                        "region": region,
                        "state_bucket_configured": bool(bucket),
                        "state_bucket_accessible": bucket_access,
                        "state_bucket_versioning": versioning,
                        "lock_table_configured": bool(table),
                        "lock_table_status": table_status,
                        "oidc_role_trust_status": "deferred-to-dedicated-check",
                    }

    overall_ready = static_ok and not errors
    status = "passed" if overall_ready else ("static-passed" if args.static_only and static_ok else "incomplete")
    report = {
        "live_aws_prerequisite_inventory": status,
        "static_contract": "passed" if static_ok else "failed",
        "repo": args.repo,
        "branch": args.branch,
        "github": github_report,
        "aws": aws_report,
        "terraform_stages": stage_report,
        "errors": errors,
        "secret_values_read": False,
        "aws_mutation": "none",
    }
    (output_dir / "prerequisite-inventory.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    summary = [
        f"live_aws_prerequisite_inventory={status}",
        f"static_contract={report['static_contract']}",
        f"terraform_stage_count={len(stage_report)}",
        f"github_status={github_report.get('status', '')}",
        f"missing_github_variable_count={len(missing_variables)}",
        f"missing_github_secret_count={len(missing_secrets)}",
        f"aws_status={aws_report.get('status', '')}",
        "secret_values_read=false",
        "aws_mutation=none",
    ]
    (output_dir / "prerequisite-summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print("\n".join(summary))
    for error in errors:
        print(f"[live-aws-prerequisite] {error}", file=sys.stderr)
    return 1 if args.fail_on_missing and not overall_ready else 0


if __name__ == "__main__":
    raise SystemExit(main())
