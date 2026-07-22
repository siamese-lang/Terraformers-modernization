#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_DIR = ROOT / ".github/workflows"
EVIDENCE_DIR = ROOT / "artifacts/aws-environment-contract"
INVENTORY_JSON = EVIDENCE_DIR / "deployment-contract-inventory.json"
INVENTORY_MD = EVIDENCE_DIR / "deployment-contract-inventory.md"
INVENTORY_SUMMARY = EVIDENCE_DIR / "deployment-contract-inventory-summary.txt"
REFERENCE_JSON = EVIDENCE_DIR / "workflow-reference-inventory.json"
REFERENCE_SUMMARY = EVIDENCE_DIR / "workflow-reference-summary.txt"
FORBIDDEN_STATIC_AWS_SECRETS = {"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY"}


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def collect_references() -> list[dict[str, object]]:
    references: list[dict[str, object]] = []
    expression_pattern = re.compile(r"\$\{\{(.*?)\}\}", re.S)
    reference_pattern = re.compile(
        r"(?<![A-Za-z0-9_])(vars|secrets)\.([A-Z][A-Z0-9_]*)"
    )
    seen: set[tuple[str, str, str, int]] = set()

    for path in sorted(WORKFLOW_DIR.glob("*.y*ml")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for expression_match in expression_pattern.finditer(text):
            expression = expression_match.group(1)
            for reference_match in reference_pattern.finditer(expression):
                offset = expression_match.start(1) + reference_match.start()
                item = (
                    reference_match.group(1),
                    reference_match.group(2),
                    path.relative_to(ROOT).as_posix(),
                    line_number(text, offset),
                )
                if item in seen:
                    continue
                seen.add(item)
                references.append(
                    {
                        "scope": item[0],
                        "name": item[1],
                        "file": item[2],
                        "line": item[3],
                    }
                )
    return references


def replace_summary_count(lines: list[str], key: str, value: int) -> list[str]:
    replacement = f"{key}={value}"
    for index, line in enumerate(lines):
        if line.startswith(key + "="):
            lines[index] = replacement
            return lines
    lines.append(replacement)
    return lines


def main() -> int:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    references = collect_references()
    variable_count = sum(item["scope"] == "vars" for item in references)
    secret_count = sum(item["scope"] == "secrets" for item in references)
    forbidden = sorted(
        {
            str(item["name"])
            for item in references
            if item["scope"] == "secrets"
        }
        & FORBIDDEN_STATIC_AWS_SECRETS
    )

    REFERENCE_JSON.write_text(
        json.dumps({"references": references}, indent=2) + "\n",
        encoding="utf-8",
    )

    if INVENTORY_JSON.exists():
        inventory = json.loads(INVENTORY_JSON.read_text(encoding="utf-8"))
        inventory.setdefault("github_actions", {})["references"] = references
        INVENTORY_JSON.write_text(
            json.dumps(inventory, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    if INVENTORY_SUMMARY.exists():
        summary_lines = INVENTORY_SUMMARY.read_text(encoding="utf-8").splitlines()
        replace_summary_count(
            summary_lines, "github_variable_reference_count", variable_count
        )
        replace_summary_count(
            summary_lines, "github_secret_reference_count", secret_count
        )
        INVENTORY_SUMMARY.write_text(
            "\n".join(summary_lines) + "\n", encoding="utf-8"
        )

    table_lines = [
        "",
        "## Reconciled GitHub Actions references",
        "",
        "| Scope | Name | File | Line |",
        "|---|---|---|---|",
    ]
    table_lines.extend(
        f"| {item['scope']} | {item['name']} | {item['file']} | {item['line']} |"
        for item in references
    )
    if INVENTORY_MD.exists():
        content = INVENTORY_MD.read_text(encoding="utf-8")
        marker = "\n## Reconciled GitHub Actions references\n"
        if marker in content:
            content = content.split(marker, 1)[0].rstrip() + "\n"
        INVENTORY_MD.write_text(
            content.rstrip() + "\n" + "\n".join(table_lines) + "\n",
            encoding="utf-8",
        )

    status = "failed" if forbidden else "passed"
    summary = [
        f"github_workflow_reference_reconciliation={status}",
        f"github_variable_reference_count={variable_count}",
        f"github_secret_reference_count={secret_count}",
        "forbidden_static_aws_secret_count=" + str(len(forbidden)),
    ]
    REFERENCE_SUMMARY.write_text("\n".join(summary) + "\n", encoding="utf-8")

    if forbidden:
        print(
            "[aws-workflow-reference] long-lived AWS credential secrets are forbidden: "
            + ", ".join(forbidden),
            file=sys.stderr,
        )
        return 1

    print(
        "[aws-workflow-reference] reconciled nested vars/secrets references: "
        f"vars={variable_count}, secrets={secret_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
