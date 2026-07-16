#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_DIR = REPO_ROOT / "artifacts" / "aws-environment-contract"
JSON_OUTPUT = EVIDENCE_DIR / "deployment-contract-inventory.json"
MARKDOWN_OUTPUT = EVIDENCE_DIR / "deployment-contract-inventory.md"
SUMMARY_OUTPUT = EVIDENCE_DIR / "deployment-contract-inventory-summary.txt"

LEGACY_RUNTIME_KEYS = {"AWS_S3_BUCKET_NAME", "FRONTEND_URL", "DOMAIN"}
FORBIDDEN_STATIC_AWS_SECRETS = {"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"}
CANONICAL_BACKEND_BASE = [
    "SPRING_DATASOURCE_URL",
    "SPRING_DATASOURCE_USERNAME",
    "SPRING_DATASOURCE_PASSWORD",
    "COGNITO_REGION",
    "COGNITO_USER_POOL_ID",
    "COGNITO_USER_POOL_CLIENT_ID",
    "COGNITO_JWKS_URL",
    "S3_BUCKET_NAME",
]
CANONICAL_FRONTEND = [
    "REACT_APP_API_BASE_URL",
    "REACT_APP_AWS_REGION",
    "REACT_APP_COGNITO_USER_POOL_ID",
    "REACT_APP_COGNITO_USER_POOL_CLIENT_ID",
]

OUTPUT_GROUPS: dict[str, tuple[str, ...]] = {
    "aws_region": ("aws_region", "region"),
    "eks_cluster": ("eks_cluster_name", "cluster_name", "eks_name"),
    "backend_ecr": ("backend_ecr_repository_url", "backend_ecr_url", "ecr_repository_url"),
    "rds_endpoint": ("rds_endpoint", "database_endpoint", "db_endpoint"),
    "rds_port": ("rds_port", "database_port", "db_port"),
    "rds_database": ("rds_database_name", "database_name", "db_name"),
    "s3_application_bucket": (
        "s3_bucket_name",
        "application_bucket_name",
        "upload_bucket_name",
        "project_bucket_name",
    ),
    "cognito_user_pool": ("cognito_user_pool_id", "user_pool_id"),
    "cognito_user_pool_client": (
        "cognito_user_pool_client_id",
        "user_pool_client_id",
        "cognito_client_id",
    ),
    "frontend_bucket": ("frontend_bucket_name", "web_bucket_name", "static_bucket_name"),
    "cloudfront_distribution": ("cloudfront_distribution_id", "distribution_id"),
    "backend_irsa_role": (
        "backend_service_account_role_arn",
        "backend_irsa_role_arn",
        "backend_role_arn",
    ),
    "runtime_secret": ("backend_runtime_secret_arn", "runtime_secret_arn", "secret_arn"),
}


def relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def iter_files(root: Path, suffixes: set[str]) -> Iterable[Path]:
    if not root.exists():
        return []
    return sorted(
        path
        for path in root.rglob("*")
        if path.is_file()
        and path.suffix in suffixes
        and ".terraform" not in path.parts
        and "node_modules" not in path.parts
        and "target" not in path.parts
        and "artifacts" not in path.parts
    )


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def collect_terraform() -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    outputs: list[dict[str, object]] = []
    variables: list[dict[str, object]] = []
    for path in iter_files(REPO_ROOT, {".tf"}):
        text = read(path)
        for match in re.finditer(r'(?m)^\s*output\s+"([^"]+)"\s*\{', text):
            outputs.append({"name": match.group(1), "file": relative(path), "line": line_number(text, match.start())})
        for match in re.finditer(r'(?m)^\s*variable\s+"([^"]+)"\s*\{', text):
            variables.append({"name": match.group(1), "file": relative(path), "line": line_number(text, match.start())})
    return outputs, variables


def collect_workflow_references() -> list[dict[str, object]]:
    references: list[dict[str, object]] = []
    workflow_root = REPO_ROOT / ".github" / "workflows"
    for path in iter_files(workflow_root, {".yml", ".yaml"}):
        text = read(path)
        for match in re.finditer(r'\$\{\{\s*(vars|secrets)\.([A-Z][A-Z0-9_]*)', text):
            references.append(
                {
                    "scope": match.group(1),
                    "name": match.group(2),
                    "file": relative(path),
                    "line": line_number(text, match.start()),
                }
            )
    return references


def collect_deploy_script_environment() -> list[dict[str, object]]:
    references: list[dict[str, object]] = []
    deploy_root = REPO_ROOT / "scripts" / "deploy"
    for path in iter_files(deploy_root, {".sh", ".py", ".ps1"}):
        text = read(path)
        matches: list[tuple[str, int, str]] = []
        if path.suffix == ".sh":
            for match in re.finditer(r'\$\{([A-Z][A-Z0-9_]*)(?::[-+?=][^}]*)?\}', text):
                matches.append((match.group(1), match.start(), "shell-parameter"))
        elif path.suffix == ".py":
            for match in re.finditer(r'os\.(?:environ(?:\.get|\[)|getenv\()\s*["\']([A-Z][A-Z0-9_]*)', text):
                matches.append((match.group(1), match.start(), "python-environment"))
        elif path.suffix == ".ps1":
            for match in re.finditer(r'\$env:([A-Z][A-Z0-9_]*)', text, re.I):
                matches.append((match.group(1).upper(), match.start(), "powershell-environment"))
        seen: set[tuple[str, int]] = set()
        for name, offset, source in matches:
            key = (name, offset)
            if key in seen:
                continue
            seen.add(key)
            references.append(
                {"name": name, "source": source, "file": relative(path), "line": line_number(text, offset)}
            )
    return references


def collect_spring_placeholders() -> list[dict[str, object]]:
    references: list[dict[str, object]] = []
    resource_root = REPO_ROOT / "backend" / "src" / "main" / "resources"
    for path in iter_files(resource_root, {".yml", ".yaml", ".properties"}):
        text = read(path)
        for match in re.finditer(r'\$\{([A-Z][A-Z0-9_]*)(?::[^}]*)?\}', text):
            references.append({"name": match.group(1), "file": relative(path), "line": line_number(text, match.start())})
    return references


def collect_kubernetes_keys() -> list[dict[str, object]]:
    keys: list[dict[str, object]] = []
    kubernetes_root = REPO_ROOT / "infra" / "kubernetes"
    for path in iter_files(kubernetes_root, {".yml", ".yaml"}):
        text = read(path)
        for match in re.finditer(r'(?m)^\s+(?:name:\s*)?([A-Z][A-Z0-9_]*)\s*:', text):
            keys.append({"name": match.group(1), "file": relative(path), "line": line_number(text, match.start())})
        for match in re.finditer(r'(?m)^\s+-\s+name:\s*([A-Z][A-Z0-9_]*)\s*$', text):
            keys.append({"name": match.group(1), "file": relative(path), "line": line_number(text, match.start())})
    return keys


def collect_frontend_environment() -> list[dict[str, object]]:
    path = REPO_ROOT / "frontend" / ".env.example"
    if not path.exists():
        return []
    text = read(path)
    return [
        {"name": match.group(1), "file": relative(path), "line": line_number(text, match.start())}
        for match in re.finditer(r'(?m)^(REACT_APP_[A-Z0-9_]+)=', text)
    ]


def group_output_status(output_names: set[str]) -> dict[str, dict[str, object]]:
    status: dict[str, dict[str, object]] = {}
    for group, aliases in OUTPUT_GROUPS.items():
        matched = sorted(name for name in output_names if name in aliases)
        status[group] = {"status": "matched" if matched else "unresolved", "matched_outputs": matched, "aliases": list(aliases)}
    return status


def markdown_table(headers: list[str], rows: list[list[object]]) -> list[str]:
    result = ["| " + " | ".join(headers) + " |", "|" + "|".join("---" for _ in headers) + "|"]
    if not rows:
        result.append("| " + " | ".join("-" for _ in headers) + " |")
    else:
        result.extend("| " + " | ".join(str(value) for value in row) + " |" for row in rows)
    return result


def main() -> int:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)

    terraform_outputs, terraform_variables = collect_terraform()
    workflow_references = collect_workflow_references()
    deploy_environment = collect_deploy_script_environment()
    spring_placeholders = collect_spring_placeholders()
    kubernetes_keys = collect_kubernetes_keys()
    frontend_environment = collect_frontend_environment()

    output_names = {str(item["name"]) for item in terraform_outputs}
    output_groups = group_output_status(output_names)
    workflow_secret_names = {
        str(item["name"]) for item in workflow_references if item["scope"] == "secrets"
    }
    active_runtime_names = {
        str(item["name"])
        for item in spring_placeholders + kubernetes_keys + deploy_environment
    }
    frontend_names = [str(item["name"]) for item in frontend_environment]

    errors: list[str] = []
    warnings: list[str] = []

    if not terraform_outputs:
        errors.append("No Terraform output blocks were found; downstream deployment values cannot be reconciled.")

    forbidden_secret_refs = sorted(workflow_secret_names & FORBIDDEN_STATIC_AWS_SECRETS)
    if forbidden_secret_refs:
        errors.append(
            "Workflow references long-lived AWS credential secrets instead of OIDC: "
            + ", ".join(forbidden_secret_refs)
        )

    active_legacy = sorted(active_runtime_names & LEGACY_RUNTIME_KEYS)
    if active_legacy:
        errors.append("Legacy runtime keys are active outside documentation: " + ", ".join(active_legacy))

    if frontend_names != CANONICAL_FRONTEND:
        errors.append(
            "Frontend build-variable contract differs from the canonical order: "
            f"expected={CANONICAL_FRONTEND}, actual={frontend_names}"
        )

    missing_spring_base = sorted(set(CANONICAL_BACKEND_BASE) - {str(item["name"]) for item in spring_placeholders})
    if missing_spring_base:
        errors.append("Spring configuration is missing canonical base placeholders: " + ", ".join(missing_spring_base))

    unresolved_groups = sorted(group for group, item in output_groups.items() if item["status"] == "unresolved")
    if unresolved_groups:
        warnings.append("Terraform output groups still unresolved: " + ", ".join(unresolved_groups))

    inventory = {
        "canonical_backend_base": CANONICAL_BACKEND_BASE,
        "canonical_frontend": CANONICAL_FRONTEND,
        "terraform": {
            "outputs": terraform_outputs,
            "variables": terraform_variables,
            "output_groups": output_groups,
        },
        "github_actions": {"references": workflow_references},
        "deploy_scripts": {"environment_references": deploy_environment},
        "spring": {"environment_placeholders": spring_placeholders},
        "kubernetes": {"environment_keys": kubernetes_keys},
        "frontend": {"build_variables": frontend_environment},
        "errors": errors,
        "warnings": warnings,
    }
    JSON_OUTPUT.write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    lines: list[str] = [
        "# AWS Deployment Contract Inventory",
        "",
        "This inventory is generated from the checked-out repository. It performs no AWS authentication, Terraform planning, image publishing, or Kubernetes mutation.",
        "",
        "## Terraform outputs",
        "",
    ]
    lines.extend(
        markdown_table(
            ["Output", "File", "Line"],
            [[item["name"], item["file"], item["line"]] for item in terraform_outputs],
        )
    )
    lines.extend(["", "## Required output groups", ""])
    lines.extend(
        markdown_table(
            ["Group", "Status", "Matched outputs"],
            [
                [group, item["status"], ", ".join(item["matched_outputs"]) or "-"]
                for group, item in sorted(output_groups.items())
            ],
        )
    )
    lines.extend(["", "## GitHub Actions repository/environment references", ""])
    lines.extend(
        markdown_table(
            ["Scope", "Name", "File", "Line"],
            [[item["scope"], item["name"], item["file"], item["line"]] for item in workflow_references],
        )
    )
    lines.extend(["", "## Deployment-script environment references", ""])
    lines.extend(
        markdown_table(
            ["Name", "Source", "File", "Line"],
            [[item["name"], item["source"], item["file"], item["line"]] for item in deploy_environment],
        )
    )
    lines.extend(["", "## Findings", ""])
    lines.append(f"- critical errors: {len(errors)}")
    lines.append(f"- unresolved warnings: {len(warnings)}")
    for error in errors:
        lines.append(f"- ERROR: {error}")
    for warning in warnings:
        lines.append(f"- WARNING: {warning}")
    MARKDOWN_OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    summary_lines = [
        "aws_deployment_contract_inventory=passed" if not errors else "aws_deployment_contract_inventory=failed",
        f"terraform_output_count={len(terraform_outputs)}",
        f"terraform_variable_count={len(terraform_variables)}",
        f"github_variable_reference_count={sum(1 for item in workflow_references if item['scope'] == 'vars')}",
        f"github_secret_reference_count={sum(1 for item in workflow_references if item['scope'] == 'secrets')}",
        f"deploy_environment_reference_count={len(deploy_environment)}",
        f"unresolved_output_group_count={len(unresolved_groups)}",
        "unresolved_output_groups=" + ",".join(unresolved_groups),
    ]
    SUMMARY_OUTPUT.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

    for warning in warnings:
        print(f"[aws-deployment-contract] WARNING: {warning}", file=sys.stderr)
    for error in errors:
        print(f"[aws-deployment-contract] ERROR: {error}", file=sys.stderr)

    if errors:
        return 1

    print("[aws-deployment-contract] repository inventory generated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
