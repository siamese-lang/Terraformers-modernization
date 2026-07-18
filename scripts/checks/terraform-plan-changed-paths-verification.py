#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SUMMARIZER = ROOT / "scripts" / "deploy" / "summarize-terraform-plan.py"
EVIDENCE_DIR = ROOT / "artifacts" / "live-deployment-plan-contract" / "changed-paths"
FIXTURE = EVIDENCE_DIR / "update-plan.json"
SUMMARY_DIR = EVIDENCE_DIR / "summary"


def main() -> int:
    if EVIDENCE_DIR.exists():
        shutil.rmtree(EVIDENCE_DIR)
    SUMMARY_DIR.mkdir(parents=True)

    fixture = {
        "format_version": "1.2",
        "terraform_version": "1.15.8",
        "resource_changes": [
            {
                "address": "aws_cloudfront_distribution.frontend",
                "type": "aws_cloudfront_distribution",
                "change": {
                    "actions": ["update"],
                    "before": {
                        "enabled": True,
                        "tags": {"Owner": "fixture-before-value"},
                        "viewer_certificate": [
                            {"minimum_protocol_version": "fixture-before-protocol"}
                        ],
                        "comment": "fixture-before-sensitive",
                    },
                    "after": {
                        "enabled": True,
                        "tags": {"Owner": "fixture-after-value"},
                        "viewer_certificate": [
                            {"minimum_protocol_version": "fixture-after-protocol"}
                        ],
                        "comment": "fixture-after-sensitive",
                    },
                    "before_sensitive": {"comment": True},
                    "after_sensitive": {"comment": True},
                },
            },
            {
                "address": "aws_iam_role.frontend_delivery",
                "type": "aws_iam_role",
                "change": {
                    "actions": ["create"],
                    "before": None,
                    "after": {"name": "fixture-role-value"},
                },
            },
        ],
    }
    FIXTURE.write_text(json.dumps(fixture, indent=2) + "\n", encoding="utf-8")

    result = subprocess.run(
        [
            sys.executable,
            str(SUMMARIZER),
            "--plan-json",
            str(FIXTURE),
            "--output-dir",
            str(SUMMARY_DIR),
            "--stage",
            "frontend-delivery",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"Summarizer failed with {result.returncode}:\nstdout={result.stdout}\nstderr={result.stderr}"
        )

    summary_json = SUMMARY_DIR / "plan-risk-summary.json"
    summary_text = SUMMARY_DIR / "plan-risk-summary.txt"
    summary_markdown = SUMMARY_DIR / "plan-risk-summary.md"
    summary = json.loads(summary_json.read_text(encoding="utf-8"))

    assert summary["resource_change_count"] == 2
    assert summary["update_resource_count"] == 1
    assert summary["raw_plan_uploaded"] is False
    assert summary["changed_values_uploaded"] is False

    actions = {item["address"]: item for item in summary["resource_actions"]}
    assert actions["aws_cloudfront_distribution.frontend"]["changed_attribute_paths"] == [
        "comment",
        "tags.Owner",
        "viewer_certificate.0.minimum_protocol_version",
    ]
    assert actions["aws_iam_role.frontend_delivery"]["changed_attribute_paths"] == []

    combined = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (summary_json, summary_text, summary_markdown)
    )
    for forbidden in (
        "fixture-before-value",
        "fixture-after-value",
        "fixture-before-protocol",
        "fixture-after-protocol",
        "fixture-before-sensitive",
        "fixture-after-sensitive",
        "fixture-role-value",
    ):
        assert forbidden not in combined, forbidden

    assert "update_resource_count=1" in summary_text.read_text(encoding="utf-8")
    assert "changed_values_uploaded=false" in summary_text.read_text(encoding="utf-8")
    assert "Changed attribute paths" in summary_markdown.read_text(encoding="utf-8")

    verification_summary = [
        "terraform_plan_changed_paths_verification=passed",
        "update_resource_count=1",
        "changed_attribute_paths_reported=true",
        "changed_attribute_values_reported=false",
        "sensitive_values_reported=false",
        "raw_plan_uploaded=false",
        "aws_mutation=none",
    ]
    (EVIDENCE_DIR / "verification-summary.txt").write_text(
        "\n".join(verification_summary) + "\n", encoding="utf-8"
    )
    print("\n".join(verification_summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
