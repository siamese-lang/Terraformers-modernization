#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SUMMARIZER = ROOT / "scripts/deploy/summarize-terraform-plan.py"
VERIFIER = ROOT / "scripts/deploy/verify-approved-terraform-apply-contract.py"
EVIDENCE_DIR = ROOT / "artifacts/approved-terraform-apply-contract"
PLAN_WORKFLOW = ROOT / ".github/workflows/aws-live-terraform-plan.yml"
APPLY_WORKFLOW = ROOT / ".github/workflows/aws-live-terraform-apply.yml"
FOUNDATION = {
    "aws_iam_role.terraform_apply": "aws_iam_role",
    "aws_iam_role_policy.terraform_apply_iam_mutation": "aws_iam_role_policy",
    "aws_iam_role_policy.terraform_apply_state_access": "aws_iam_role_policy",
    "aws_iam_role_policy_attachment.terraform_apply_read_only": "aws_iam_role_policy_attachment",
}


def run(args: list[str], success: bool = True) -> None:
    result = subprocess.run(args, text=True, capture_output=True, check=False)
    if (success and result.returncode != 0) or (not success and result.returncode == 0):
        raise RuntimeError(f"unexpected result: {' '.join(args)}\nstdout={result.stdout}\nstderr={result.stderr}")


def contains(text: str, needle: str) -> None:
    if needle not in text:
        raise AssertionError(f"missing workflow contract text: {needle}")


def verify_workflow() -> None:
    apply = APPLY_WORKFLOW.read_text(encoding="utf-8")
    plan = PLAN_WORKFLOW.read_text(encoding="utf-8")
    for text in (
        "- foundation", "- eks-runtime", "default: eks-runtime",
        "foundation apply is only supported by direct workflow_dispatch.",
        "aws-live-plan' || 'aws-live-apply", "infra/terraform/bootstrap/aws-live-foundation",
        "state_component=bootstrap", "AWS_LIVE_FOUNDATION_TFVARS_B64",
        "APPLY_REVIEWED_FOUNDATION_CREATE", "APPLY_REVIEWED_IN_PLACE_UPDATE",
        "${STATE_PREFIX}/${STATE_COMPONENT}/terraform.tfstate", "use_lockfile = true",
        "FOUNDATION_TFVARS_B64: ${{ secrets.AWS_LIVE_FOUNDATION_TFVARS_B64 }}",
        "EKS_TFVARS_B64: ${{ secrets.AWS_LIVE_EKS_TFVARS_B64 }}",
        "AWS_LIVE_FOUNDATION_TFVARS_B64 secret is required.",
        "temporary_bootstrap_permission_cleanup=external-required",
        "post_apply_full_plan=no-changes",
    ):
        contains(apply, text)
    contains(plan, "uses: ./.github/workflows/aws-live-terraform-apply.yml")
    contains(plan, "inputs.plan_stage == 'eks-runtime'")
    contains(plan, "execute_approved_apply requires plan_stage=eks-runtime.")
    for forbidden in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
        assert forbidden not in apply, forbidden
    upload = apply.split("Upload sanitized apply evidence", 1)[1]
    for forbidden in ("live.tfplan", "live-plan.json", "live.auto.tfvars", "backend.hcl", "post-apply-plan.txt"):
        assert forbidden not in upload, forbidden


def fixture(address: str, resource_type: str, actions: list[str]) -> dict:
    return {"format_version": "1.2", "terraform_version": "1.15.8", "resource_changes": [{"address": address, "type": resource_type, "change": {"actions": actions, "before": None if actions == ["create"] else {"policy": "before"}, "after": {"name": address}}}]}


def verify_contract(plan: dict, contract: str, stage: str, success: bool, extra: list[str] | None = None) -> None:
    path = EVIDENCE_DIR / f"{contract}-{stage}.json"
    output = EVIDENCE_DIR / f"{contract}-{stage}-summary"
    path.write_text(json.dumps(plan), encoding="utf-8")
    run([sys.executable, str(SUMMARIZER), "--plan-json", str(path), "--output-dir", str(output), "--stage", stage])
    args = [sys.executable, str(VERIFIER), "--summary-json", str(output / "plan-risk-summary.json"), "--summary-txt", str(output / "plan-risk-summary.txt"), "--contract", contract, "--stage", stage]
    run(args + (extra or []), success)


def main() -> int:
    verify_workflow()
    if EVIDENCE_DIR.exists(): shutil.rmtree(EVIDENCE_DIR)
    EVIDENCE_DIR.mkdir(parents=True)

    foundation_changes = [
        {"address": address, "type": kind, "change": {"actions": ["create"], "before": None, "after": {"name": address}}}
        for address, kind in FOUNDATION.items()
    ]
    positive = {"format_version": "1.2", "terraform_version": "1.15.8", "resource_changes": foundation_changes}
    verify_contract(positive, "foundation-apply-role-bootstrap", "foundation", True)
    extra = dict(foundation_changes[0]); extra["address"] = "aws_iam_role.extra"
    verify_contract({**positive, "resource_changes": foundation_changes + [extra]}, "foundation-apply-role-bootstrap", "foundation", False)
    verify_contract({**positive, "resource_changes": foundation_changes[:-1]}, "foundation-apply-role-bootstrap", "foundation", False)
    updated = json.loads(json.dumps(positive)); updated["resource_changes"][0]["change"] = {"actions": ["update"], "before": {"name": "old"}, "after": {"name": "new"}}
    verify_contract(updated, "foundation-apply-role-bootstrap", "foundation", False)
    wrong = json.loads(json.dumps(positive)); wrong["resource_changes"][0]["address"] = "aws_iam_role.wrong"
    verify_contract(wrong, "foundation-apply-role-bootstrap", "foundation", False)

    eks = fixture("aws_iam_policy.backend_runtime_access", "aws_iam_policy", ["update"])
    eks["resource_changes"][0]["change"]["after"] = {"policy": "after"}
    verify_contract(eks, "eks-runtime-backend-policy-update", "eks-runtime", True, ["--approved-resource", "aws_iam_policy.backend_runtime_access", "--approved-changed-path", "policy"])
    verify_contract(eks, "eks-runtime-backend-policy-update", "eks-runtime", False, ["--approved-resource", "aws_iam_policy.backend_runtime_access", "--approved-changed-path", "tags.Owner"])

    summary = [
        "approved_terraform_apply_contract_verification=passed",
        "foundation_positive_verification=passed", "foundation_negative_extra_resource=passed",
        "foundation_negative_missing_resource=passed", "foundation_negative_update=passed",
        "foundation_negative_wrong_address=passed", "eks_runtime_positive_and_negative_verification=passed",
        "raw_plan_uploaded=false", "aws_mutation=none", "kubernetes_mutation=none",
    ]
    (EVIDENCE_DIR / "verification-summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print("\n".join(summary))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
