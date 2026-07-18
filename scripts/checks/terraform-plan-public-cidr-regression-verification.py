#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SUMMARIZER = ROOT / "scripts" / "deploy" / "summarize-terraform-plan.py"
EVIDENCE_DIR = ROOT / "artifacts" / "live-deployment-plan-contract" / "public-cidr-regression"
FIXTURE_DIR = EVIDENCE_DIR / "fixtures"
SUMMARY_FILES = ("plan-risk-summary.json", "plan-risk-summary.md", "plan-risk-summary.txt")


def write_plan(path: Path, cidr: str) -> None:
    plan = {
        "format_version": "1.2",
        "terraform_version": "1.9.8",
        "resource_changes": [
            {
                "address": "aws_vpc_security_group_ingress_rule.private_api",
                "type": "aws_vpc_security_group_ingress_rule",
                "change": {
                    "actions": ["create"],
                    "after": {
                        "cidr_ipv4": "10.40.0.0/16",
                        "description": "private api ingress",
                        "nested": {
                            "cidrs": [cidr],
                            "metadata": [{"name": "safe", "values": ["10.41.0.0/16"]}],
                        },
                    },
                },
            },
            {
                "address": "aws_eks_cluster.runtime",
                "type": "aws_eks_cluster",
                "change": {
                    "actions": ["create"],
                    "after": {
                        "name": "runtime",
                        "vpc_config": [
                            {
                                "endpoint_public_access": True,
                                "public_access_cidrs": ["10.42.0.0/16"],
                                "nested": {"private_cidrs": ["10.43.0.0/16"]},
                            }
                        ],
                    },
                },
            },
        ],
    }
    path.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")


def assert_summary_files(output_dir: Path) -> None:
    for filename in SUMMARY_FILES:
        summary_file = output_dir / filename
        if not summary_file.is_file() or summary_file.stat().st_size == 0:
            raise AssertionError(f"missing non-empty summary file: {summary_file}")


def run_summarizer(plan_path: Path, output_dir: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "python3",
            str(SUMMARIZER),
            "--plan-json",
            str(plan_path),
            "--output-dir",
            str(output_dir),
            "--stage",
            "network",
        ],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def main() -> int:
    shutil.rmtree(EVIDENCE_DIR, ignore_errors=True)
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)

    private_plan = FIXTURE_DIR / "nested-private-cidr-plan.json"
    private_output = EVIDENCE_DIR / "nested-private-cidr-summary"
    write_plan(private_plan, "10.44.0.0/16")
    private_result = run_summarizer(private_plan, private_output)
    if private_result.returncode != 0:
        raise AssertionError(
            "private nested CIDR fixture failed unexpectedly:\n"
            f"stdout={private_result.stdout}\nstderr={private_result.stderr}"
        )
    assert_summary_files(private_output)

    public_plan = FIXTURE_DIR / "nested-public-cidr-plan.json"
    public_output = EVIDENCE_DIR / "nested-public-cidr-summary"
    write_plan(public_plan, "0.0.0.0/0")
    public_result = run_summarizer(public_plan, public_output)
    if public_result.returncode != 1:
        raise AssertionError(
            "public nested CIDR fixture did not fail the risk gate:\n"
            f"returncode={public_result.returncode}\nstdout={public_result.stdout}\nstderr={public_result.stderr}"
        )
    assert_summary_files(public_output)
    text_summary = (public_output / "plan-risk-summary.txt").read_text(encoding="utf-8")
    for expected in ("public_exposure_finding_count=1", "failure_reasons=public-exposure"):
        if expected not in text_summary.splitlines():
            raise AssertionError(f"missing public risk summary line: {expected}")

    json_summary = json.loads((public_output / "plan-risk-summary.json").read_text(encoding="utf-8"))
    if len(json_summary.get("public_exposure_findings", [])) != 1:
        raise AssertionError("expected exactly one public exposure finding in JSON summary")

    (EVIDENCE_DIR / "verification-summary.txt").write_text(
        "terraform_plan_public_cidr_regression=passed\n"
        "private_nested_cidr_summary=generated\n"
        "public_nested_cidr_summary=generated\n"
        "public_exposure_finding_count=1\n",
        encoding="utf-8",
    )
    print("[terraform-plan-public-cidr-regression] verification completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
