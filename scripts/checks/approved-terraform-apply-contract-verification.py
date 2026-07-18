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
PLAN_WORKFLOW = ROOT / ".github" / "workflows" / "aws-live-terraform-plan.yml"
APPLY_WORKFLOW = ROOT / ".github" / "workflows" / "aws-live-terraform-apply.yml"
CONTRACT_WORKFLOW = ROOT / ".github" / "workflows" / "live-deployment-plan-contract-verification.yml"


def run_command(args: list[str], expect_success: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, text=True, capture_output=True, check=False)
    if expect_success and result.returncode != 0:
        raise RuntimeError(
            f"Command failed with {result.returncode}: {' '.join(args)}\nstdout={result.stdout}\nstderr={result.stderr}"
        )
    if not expect_success and result.returncode == 0:
        raise RuntimeError(f"Command unexpectedly passed: {' '.join(args)}\nstdout={result.stdout}")
    return result


def assert_contains(text: str, needle: str, context: str) -> None:
    if needle not in text:
        raise AssertionError(f"Missing {context}: {needle}")


def verify_workflow_contracts() -> None:
    plan_workflow = PLAN_WORKFLOW.read_text(encoding="utf-8")
    apply_workflow = APPLY_WORKFLOW.read_text(encoding="utf-8")
    contract_workflow = CONTRACT_WORKFLOW.read_text(encoding="utf-8")

    for input_name in (
        "execute_live_plan:",
        "plan_stage:",
        "expected_aws_account_id:",
        "allow_destructive:",
        "allow_optional_adapters:",
        "execute_approved_apply:",
        "expected_head_sha:",
        "approved_resource_address:",
        "approved_changed_attribute_path:",
        "approval_confirmation:",
    ):
        assert_contains(plan_workflow, input_name, "plan workflow bootstrap input")

    assert_contains(plan_workflow, "execute_live_plan:\n        description:", "plan workflow execute_live_plan input")
    assert_contains(plan_workflow, "default: false", "plan-only false default")
    assert_contains(plan_workflow, "execute_approved_apply:\n        description:", "approved apply bootstrap input")
    assert_contains(plan_workflow, "uses: ./.github/workflows/aws-live-terraform-apply.yml", "local reusable apply workflow call")
    assert_contains(plan_workflow, "secrets: inherit", "reusable apply workflow inherited secrets")
    assert_contains(plan_workflow, "execute_live_plan and execute_approved_apply must not both be true.", "explicit mutually exclusive execute failure")
    assert_contains(plan_workflow, "execute_approved_apply requires plan_stage=eks-runtime.", "explicit apply stage failure")
    assert_contains(plan_workflow, "if: ${{ inputs.execute_approved_apply && !inputs.execute_live_plan && inputs.plan_stage == 'eks-runtime' }}", "strict apply caller condition")

    assert_contains(apply_workflow, "workflow_call:", "apply workflow reusable trigger")
    for contract in (
        "execute_approved_apply:\n        description:",
        "expected_aws_account_id:\n        description:",
        "expected_head_sha:\n        description:",
        "apply_stage:\n        description:",
        "approved_resource_address:\n        description:",
        "approved_changed_attribute_path:\n        description:",
        "approval_confirmation:\n        description:",
    ):
        assert_contains(apply_workflow, contract, "apply workflow_call input contract")

    assert_contains(apply_workflow, 'POST_APPLY_PLAN="${RUNNER_TEMP}/post-apply-plan.txt"', "runner-temp post-apply raw output")
    assert "artifacts/aws-live-terraform-apply/post-apply-summary.txt" not in apply_workflow
    assert "artifacts/aws-live-terraform-apply/post-apply-plan.txt" not in apply_workflow
    upload_section = apply_workflow.split("Upload sanitized apply evidence", 1)[1]
    assert "post-apply-plan.txt" not in upload_section
    assert "post-apply-summary.txt" not in upload_section
    assert "post-apply-status.txt" in upload_section

    for forbidden in ("cat", "tail", "grep", "rg"):
        for line in apply_workflow.splitlines():
            if "post-apply-plan.txt" in line or "POST_APPLY_PLAN" in line:
                stripped = line.strip()
                assert not stripped.startswith(f"{forbidden} "), stripped
                assert f" {forbidden} " not in stripped, stripped

    for status in (
        "post_apply_full_plan=no-changes",
        "post_apply_full_plan=changes-remain",
        "post_apply_full_plan=verification-failed",
    ):
        assert_contains(apply_workflow, status, "sanitized post-apply status")

    assert_contains(contract_workflow, "docker://rhysd/actionlint:1.7.7", "pinned actionlint Docker image")
    assert_contains(contract_workflow, "args: -color", "actionlint scans all workflows")


def main() -> int:
    verify_workflow_contracts()

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
        "plan_workflow_bootstrap_inputs=present",
        "plan_workflow_calls_reusable_apply=true",
        "apply_workflow_call_contract=present",
        "post_apply_raw_output_uploaded=false",
        "actionlint_ci_step=present",
    ]
    (EVIDENCE_DIR / "verification-summary.txt").write_text(
        "\n".join(verification_summary) + "\n", encoding="utf-8"
    )
    print("\n".join(verification_summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
