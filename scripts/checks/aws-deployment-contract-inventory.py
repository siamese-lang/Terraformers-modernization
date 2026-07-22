#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_DIR = REPO_ROOT / "artifacts" / "aws-environment-contract"
JSON_OUTPUT = EVIDENCE_DIR / "deployment-contract-inventory.json"
MARKDOWN_OUTPUT = EVIDENCE_DIR / "deployment-contract-inventory.md"
SUMMARY_OUTPUT = EVIDENCE_DIR / "deployment-contract-inventory-summary.txt"

LEGACY_RUNTIME_KEYS = {"AWS_S3_BUCKET_NAME", "FRONTEND_URL", "DOMAIN"}
FORBIDDEN_STATIC_AWS_SECRETS = {"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"}
REQUIRED_ENV_SOURCE = "terraformers.runtime.required-env"
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
    "aws_region": ("aws_region", "region", "cognito_region"),
    "eks_cluster": ("eks_cluster_name", "cluster_name", "eks_name"),
    "backend_ecr": (
        "backend_image_repository_url",
        "backend_ecr_repository_url",
        "backend_ecr_url",
        "ecr_repository_url",
    ),
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
    "cloudfront_vpc_origin": ("backend_vpc_origin_id",),
    "backend_origin_load_balancer": (
        "backend_origin_load_balancer_arn",
        "backend_origin_load_balancer_dns_name",
    ),
    "load_balancer_controller_irsa": ("load_balancer_controller_irsa_role_arn",),
    "backend_origin_security_group": ("backend_origin_alb_security_group_id",),
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


def records(
    path: Path,
    text: str,
    pattern: str,
    *,
    name_group: int = 1,
    offset_base: int = 0,
    **extra: object,
) -> list[dict[str, object]]:
    return [
        {
            "name": match.group(name_group),
            "file": relative(path),
            "line": line_number(text, offset_base + match.start()),
            **extra,
        }
        for match in re.finditer(pattern, text[offset_base:])
    ]


def collect_terraform() -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    outputs: list[dict[str, object]] = []
    variables: list[dict[str, object]] = []
    for path in iter_files(REPO_ROOT, {".tf"}):
        text = read(path)
        outputs.extend(records(path, text, r'(?m)^\s*output\s+"([^"]+)"\s*\{'))
        variables.extend(records(path, text, r'(?m)^\s*variable\s+"([^"]+)"\s*\{'))
    return outputs, variables


def collect_workflow_references() -> list[dict[str, object]]:
    references: list[dict[str, object]] = []
    for path in iter_files(REPO_ROOT / ".github" / "workflows", {".yml", ".yaml"}):
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
    for path in iter_files(REPO_ROOT / "scripts" / "deploy", {".sh", ".py", ".ps1"}):
        text = read(path)
        matches: list[tuple[str, int, str]] = []
        if path.suffix == ".sh":
            matches.extend(
                (match.group(1), match.start(), "shell-parameter")
                for match in re.finditer(r'\$\{([A-Z][A-Z0-9_]*)(?::[-+?=][^}]*)?\}', text)
            )
        elif path.suffix == ".py":
            for pattern in (
                r'os\.(?:environ\.get|getenv)\(\s*["\']([A-Z][A-Z0-9_]*)["\']',
                r'os\.environ\[\s*["\']([A-Z][A-Z0-9_]*)["\']\s*\]',
            ):
                matches.extend(
                    (match.group(1), match.start(), "python-environment")
                    for match in re.finditer(pattern, text)
                )
        elif path.suffix == ".ps1":
            matches.extend(
                (match.group(1).upper(), match.start(), "powershell-environment")
                for match in re.finditer(r'\$env:([A-Z][A-Z0-9_]*)', text, re.I)
            )
        for name, offset, source in sorted(set(matches), key=lambda item: (item[1], item[0])):
            references.append(
                {"name": name, "source": source, "file": relative(path), "line": line_number(text, offset)}
            )
    return references


def collect_spring_placeholders() -> list[dict[str, object]]:
    references: list[dict[str, object]] = []
    for path in iter_files(REPO_ROOT / "backend" / "src" / "main" / "resources", {".yml", ".yaml", ".properties"}):
        text = read(path)
        references.extend(records(path, text, r'\$\{([A-Z][A-Z0-9_]*)'))
    return references


def collect_yaml_string_list(
    path: Path,
    key_path: tuple[str, ...],
) -> list[dict[str, object]]:
    text = read(path)
    stack: list[tuple[int, str]] = []
    target_indent: int | None = None
    target_found = False
    references: list[dict[str, object]] = []
    offset = 0

    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            offset += len(line)
            continue

        leading = re.match(r"^[ ]*", line)
        indent = len(leading.group(0)) if leading else 0

        if target_found:
            if indent <= (target_indent if target_indent is not None else -1):
                break

            item_match = re.match(
                r"^[ ]*-[ ]*[\"']?([A-Z][A-Z0-9_]*)[\"']?[ ]*(?:#.*)?(?:\r?\n)?$",
                line,
            )
            if item_match:
                references.append(
                    {
                        "name": item_match.group(1),
                        "file": relative(path),
                        "line": line_number(text, offset + item_match.start(1)),
                        "source": REQUIRED_ENV_SOURCE,
                    }
                )
                offset += len(line)
                continue

            raise ValueError(
                f"{relative(path)} contains a non-string entry under {'.'.join(key_path)} "
                f"at line {line_number(text, offset)}"
            )

        mapping_match = re.match(
            r"^([ ]*)([A-Za-z0-9_-]+):[ ]*(?:#.*)?(?:\r?\n)?$",
            line,
        )
        if mapping_match:
            mapping_indent = len(mapping_match.group(1))
            while stack and stack[-1][0] >= mapping_indent:
                stack.pop()
            stack.append((mapping_indent, mapping_match.group(2)))

            if tuple(key for _, key in stack) == key_path:
                target_found = True
                target_indent = mapping_indent

        offset += len(line)

    return references


def collect_spring_required_env() -> list[dict[str, object]]:
    path = REPO_ROOT / "backend" / "src" / "main" / "resources" / "application-prod.yml"
    return collect_yaml_string_list(path, ("terraformers", "runtime", "required-env"))


def collect_kubernetes_keys() -> list[dict[str, object]]:
    references: list[dict[str, object]] = []
    for path in iter_files(REPO_ROOT / "infra" / "kubernetes", {".yml", ".yaml"}):
        text = read(path)
        references.extend(records(path, text, r'(?m)^\s*-?\s*name:\s*([A-Z][A-Z0-9_]*)\s*$'))
    return references


def collect_frontend_environment() -> list[dict[str, object]]:
    path = REPO_ROOT / "frontend" / ".env.example"
    text = read(path)
    return records(path, text, r'(?m)^(REACT_APP_[A-Z0-9_]+)=')


def group_output_status(output_names: set[str]) -> dict[str, dict[str, object]]:
    return {
        group: {
            "status": "resolved" if any(name in output_names for name in names) else "unresolved",
            "matched_outputs": sorted(name for name in names if name in output_names),
        }
        for group, names in OUTPUT_GROUPS.items()
    }


def markdown_table(headers: list[str], rows: list[list[object]]) -> list[str]:
    return [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
        *["| " + " | ".join(str(value) for value in row) + " |" for row in rows],
    ]


def main() -> int:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)

    terraform_outputs, terraform_variables = collect_terraform()
    workflow_references = collect_workflow_references()
    deploy_environment = collect_deploy_script_environment()
    spring_placeholders = collect_spring_placeholders()
    try:
        spring_required_env = collect_spring_required_env()
    except ValueError as error:
        print(f"[aws-deployment-contract] ERROR: {error}", file=sys.stderr)
        return 1
    kubernetes_keys = collect_kubernetes_keys()
    frontend_environment = collect_frontend_environment()

    output_names = {str(item["name"]) for item in terraform_outputs}
    output_groups = group_output_status(output_names)
    workflow_secret_names = {
        str(item["name"]) for item in workflow_references if item["scope"] == "secrets"
    }
    runtime_names = {
        str(item["name"])
        for item in spring_placeholders + spring_required_env + kubernetes_keys
    }
    frontend_names = [str(item["name"]) for item in frontend_environment]
    required_env_names = [str(item["name"]) for item in spring_required_env]

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

    active_legacy = sorted(runtime_names & LEGACY_RUNTIME_KEYS)
    if active_legacy:
        errors.append("Legacy keys are active in Spring/Kubernetes runtime configuration: " + ", ".join(active_legacy))

    deploy_legacy = sorted({str(item["name"]) for item in deploy_environment} & LEGACY_RUNTIME_KEYS)
    if deploy_legacy:
        warnings.append(
            "Deployment scripts reference legacy-named inputs; verify they are infrastructure-only and never injected into the backend Secret: "
            + ", ".join(deploy_legacy)
        )

    if required_env_names != CANONICAL_BACKEND_BASE:
        errors.append(
            "application-prod.yml required-env differs from the canonical backend base contract: "
            f"expected={CANONICAL_BACKEND_BASE}, actual={required_env_names}"
        )

    if frontend_names != CANONICAL_FRONTEND:
        errors.append(
            "Frontend build-variable contract differs from the canonical order: "
            f"expected={CANONICAL_FRONTEND}, actual={frontend_names}"
        )

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
        "spring": {
            "required_env_source": REQUIRED_ENV_SOURCE,
            "required_env": spring_required_env,
            "environment_placeholders": spring_placeholders,
        },
        "kubernetes": {"environment_keys": kubernetes_keys},
        "frontend": {"build_variables": frontend_environment},
        "errors": errors,
        "warnings": warnings,
    }
    JSON_OUTPUT.write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    lines = [
        "# AWS Deployment Contract Inventory",
        "",
        "This inventory is generated from the checked-out repository. It performs no AWS authentication, Terraform planning, image publishing, or Kubernetes mutation.",
        "",
        "## Terraform outputs",
        "",
        *markdown_table(
            ["Output", "File", "Line"],
            [[item["name"], item["file"], item["line"]] for item in terraform_outputs],
        ),
        "",
        "## Required output groups",
        "",
        *markdown_table(
            ["Group", "Status", "Matched outputs"],
            [
                [group, item["status"], ", ".join(item["matched_outputs"]) or "-"]
                for group, item in sorted(output_groups.items())
            ],
        ),
        "",
        "## Production required environment",
        "",
        f"Source: `{REQUIRED_ENV_SOURCE}` in `backend/src/main/resources/application-prod.yml`.",
        "",
        *markdown_table(
            ["Key", "File", "Line"],
            [[item["name"], item["file"], item["line"]] for item in spring_required_env],
        ),
        "",
        "## GitHub Actions repository/environment references",
        "",
        *markdown_table(
            ["Scope", "Name", "File", "Line"],
            [[item["scope"], item["name"], item["file"], item["line"]] for item in workflow_references],
        ),
        "",
        "## Deployment-script environment references",
        "",
        *markdown_table(
            ["Name", "Source", "File", "Line"],
            [[item["name"], item["source"], item["file"], item["line"]] for item in deploy_environment],
        ),
        "",
        "## Findings",
        "",
        f"- critical errors: {len(errors)}",
        f"- unresolved warnings: {len(warnings)}",
        *[f"- ERROR: {error}" for error in errors],
        *[f"- WARNING: {warning}" for warning in warnings],
    ]
    MARKDOWN_OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    summary_lines = [
        "aws_deployment_contract_inventory=passed" if not errors else "aws_deployment_contract_inventory=failed",
        f"terraform_output_count={len(terraform_outputs)}",
        f"terraform_variable_count={len(terraform_variables)}",
        f"github_variable_reference_count={sum(1 for item in workflow_references if item['scope'] == 'vars')}",
        f"github_secret_reference_count={sum(1 for item in workflow_references if item['scope'] == 'secrets')}",
        f"deploy_environment_reference_count={len(deploy_environment)}",
        f"required_env_source={REQUIRED_ENV_SOURCE}",
        f"canonical_required_env_count={len(spring_required_env)}",
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
