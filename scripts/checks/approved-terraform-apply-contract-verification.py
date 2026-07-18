#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SUMMARIZER = ROOT / "scripts" / "deploy" / "summarize-terraform-plan.py"
VERIFIER = ROOT / "scripts" / "deploy" / "verify-approved-terraform-apply-contract.py"
EVIDENCE_DIR = ROOT / "artifacts" / "approved-terraform-apply-contract"
FIXTURE = EVIDENCE_DIR / "approved-update-plan.json"
SUMMARY_DIR = EVIDENCE_DIR / "summary"


def run_command(args: list[str], expect_success: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, text=True, capture_output=True, check=False)
    if expect_success and result.returncode != 0:
        raise RuntimeError(
            f"Command failed with {result.returncode}: {' '.join(args)}\nstdout={result.stdout}\nstderr={result.stderr}"
        )
    if not expect_success and result.returncode == 0:
        raise RuntimeError(f"Command unexpectedly passed: {' '.join(args)}\nstdout={result.stdout}")
    return result


def main() -> int:
    if EVIDENCE_DIR.exists():
        shutil.rmtree(EVIDENCE_DIR)
    SUMMARY_DIR.mkdir(parents=True)

    fixture = {
        "format_version": "1.2",
        "terraform_version": "1.15.8",
        "resource_changes": [
            {
                "address": "aws_iam_policy.backend_runtime_access",
                "type": "aws_iam_policy",
                "change": {
                    "actions": ["update"],
                    "before": {"policy": "fixture-before-policy"},
                    "after": {"policy": "fixture-after-policy-with-bedrock-invokemodel"},
                },
            }
        ],
    }
    FIXTURE.write_text(json.dumps(fixture, indent=2) + "\n", encoding="utf-8")

    run_command(
        [
            sys.executable,
            str(SUMMARIZER),
            "--plan-json",
            str(FIXTURE),
            "--output-dir",
            str(SUMMARY_DIR),
            "--stage",
            "eks-runtime",
        ]
    )
    run_command(
        [
            sys.executable,
            str(VERIFIER),
            "--summary-json",
            str(SUMMARY_DIR / "plan-risk-summary.json"),
            "--summary-txt",
            str(SUMMARY_DIR / "plan-risk-summary.txt"),
            "--stage",
            "eks-runtime",
            "--approved-resource",
            "aws_iam_policy.backend_runtime_access",
            "--approved-changed-path",
            "policy",
        ]
    )
    run_command(
        [
            sys.executable,
            str(VERIFIER),
            "--summary-json",
            str(SUMMARY_DIR / "plan-risk-summary.json"),
            "--summary-txt",
            str(SUMMARY_DIR / "plan-risk-summary.txt"),
            "--stage",
            "eks-runtime",
            "--approved-resource",
            "aws_iam_policy.backend_runtime_access",
            "--approved-changed-path",
            "tags.Owner",
        ],
        expect_success=False,
    )

    combined = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (
            SUMMARY_DIR / "plan-risk-summary.json",
            SUMMARY_DIR / "plan-risk-summary.txt",
            SUMMARY_DIR / "plan-risk-summary.md",
        )
    )
    for forbidden in ("fixture-before-policy", "fixture-after-policy-with-bedrock-invokemodel"):
        assert forbidden not in combined, forbidden

    verification_summary = [
        "approved_terraform_apply_contract_verification=passed",
        "approved_resource=aws_iam_policy.backend_runtime_access",
        "approved_action=update",
        "approved_changed_path=policy",
        "negative_changed_path_verification=passed",
        "raw_plan_uploaded=false",
        "aws_mutation=none",
        "kubernetes_mutation=none",
    ]
    (EVIDENCE_DIR / "verification-summary.txt").write_text(
        "\n".join(verification_summary) + "\n", encoding="utf-8"
    )
    print("\n".join(verification_summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
