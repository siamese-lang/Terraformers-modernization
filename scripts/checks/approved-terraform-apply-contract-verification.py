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
RAG_CREATES = {
    "aws_codebuild_project.corpus_ingestion": "aws_codebuild_project", "aws_iam_policy.backend_rag_runtime": "aws_iam_policy", "aws_iam_policy.codebuild_ingestion": "aws_iam_policy", "aws_iam_policy.corpus_ingestion": "aws_iam_policy", "aws_iam_role.codebuild_ingestion": "aws_iam_role", "aws_iam_role.corpus_ingestion": "aws_iam_role", "aws_iam_role_policy_attachment.backend_rag_runtime": "aws_iam_role_policy_attachment", "aws_iam_role_policy_attachment.codebuild_ingestion": "aws_iam_role_policy_attachment", "aws_iam_role_policy_attachment.corpus_ingestion": "aws_iam_role_policy_attachment", "aws_opensearchserverless_access_policy.data": "aws_opensearchserverless_access_policy", "aws_opensearchserverless_collection.references": "aws_opensearchserverless_collection", "aws_opensearchserverless_security_policy.encryption": "aws_opensearchserverless_security_policy", "aws_opensearchserverless_security_policy.network": "aws_opensearchserverless_security_policy", "aws_opensearchserverless_vpc_endpoint.collection": "aws_opensearchserverless_vpc_endpoint", "aws_s3_bucket.corpus": "aws_s3_bucket", "aws_s3_bucket_ownership_controls.corpus": "aws_s3_bucket_ownership_controls", "aws_s3_bucket_public_access_block.corpus": "aws_s3_bucket_public_access_block", "aws_s3_bucket_server_side_encryption_configuration.corpus": "aws_s3_bucket_server_side_encryption_configuration", "aws_s3_bucket_versioning.corpus": "aws_s3_bucket_versioning", "aws_security_group.aoss_vpc_endpoint": "aws_security_group", "aws_security_group.codebuild_ingestion": "aws_security_group", "aws_vpc_security_group_ingress_rule.aoss_from_codebuild": "aws_vpc_security_group_ingress_rule",
}
RAG_READS = ("data.aws_iam_policy_document.backend_rag_runtime", "data.aws_iam_policy_document.codebuild_ingestion", "data.aws_iam_policy_document.corpus_ingestion")
RAG_RECOVERY_CREATES = {
    address: resource_type for address, resource_type in RAG_CREATES.items()
    if address not in {
        "aws_iam_role.codebuild_ingestion", "aws_iam_role.corpus_ingestion",
        "aws_opensearchserverless_security_policy.encryption", "aws_s3_bucket.corpus",
        "aws_s3_bucket_ownership_controls.corpus", "aws_s3_bucket_public_access_block.corpus",
        "aws_s3_bucket_versioning.corpus",
    }
}
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
        "- foundation", "- eks-runtime", "- rag-runtime", "default: eks-runtime",
        "CALLER_WORKFLOW_REF: ${{ github.workflow_ref }}",
        "foundation apply requires workflow_dispatch.",
        "${GITHUB_REPOSITORY}/.github/workflows/aws-live-terraform-apply.yml@",
        "foundation apply must be dispatched directly from aws-live-terraform-apply.yml.",
        "aws-live-plan' || 'aws-live-apply", "infra/terraform/bootstrap/aws-live-foundation",
        "state_component=bootstrap", "AWS_LIVE_FOUNDATION_TFVARS_B64",
        "APPLY_REVIEWED_FOUNDATION_CREATE", "APPLY_REVIEWED_RAG_APPLY_PERMISSION_CREATE", "APPLY_REVIEWED_RAG_APPLY_PERMISSION_UPDATE", "foundation-rag-apply-permission-create", "foundation-rag-apply-permission-update", "APPLY_REVIEWED_IN_PLACE_UPDATE", "APPLY_REVIEWED_RAG_RUNTIME_CREATE", "APPLY_REVIEWED_RAG_RUNTIME_RECOVERY", "rag-runtime-reviewed-create", "rag-runtime-reviewed-recovery",
        "${STATE_PREFIX}/${STATE_COMPONENT}/terraform.tfstate", "use_lockfile = true",
        "FOUNDATION_TFVARS_B64: ${{ secrets.AWS_LIVE_FOUNDATION_TFVARS_B64 }}",
        "EKS_TFVARS_B64: ${{ secrets.AWS_LIVE_EKS_TFVARS_B64 }}", "RAG_TFVARS_B64: ${{ secrets.AWS_LIVE_RAG_TFVARS_B64 }}", "AWS_LIVE_RAG_TFVARS_B64 secret is required.",
        "AWS_LIVE_FOUNDATION_TFVARS_B64 secret is required.",
        "temporary_bootstrap_permission_cleanup=external-required",
        "post_apply_full_plan=no-changes",
    ):
        contains(apply, text)
    contains(plan, "uses: ./.github/workflows/aws-live-terraform-apply.yml")
    assert "foundation apply requires workflow_dispatch." not in plan
    contains(plan, "inputs.plan_stage == 'eks-runtime' || inputs.plan_stage == 'rag-runtime'")
    contains(plan, "execute_approved_apply requires plan_stage=eks-runtime or rag-runtime.")
    contains(plan, "APPLY_REVIEWED_RAG_RUNTIME_CREATE")
    contains(plan, "APPLY_REVIEWED_RAG_RUNTIME_RECOVERY")
    contains(plan, "expected_head_sha is required for execute_approved_apply.")
    summary_case = apply.split('case "${APPLY_CONTRACT}" in', 1)[1].split('            esac', 1)[0]
    expected_summary_branches = {
        "foundation-rag-apply-permission-create": (
            "approved_action=create", "approved_resource=aws_iam_role_policy.terraform_apply_rag_runtime_create", "approved_resource_count=1", "environment_gate=aws-live-plan",
        ),
        "foundation-rag-apply-permission-update": (
            "approved_action=update", "approved_resource=aws_iam_role_policy.terraform_apply_rag_runtime_create", "approved_changed_path=policy", "approved_resource_count=1", "environment_gate=aws-live-plan",
        ),
        "foundation-apply-role-bootstrap": ("approved_action=create", "approved_resource_count=4", "environment_gate=aws-live-plan"),
        "rag-runtime-reviewed-create": ("approved_action=create-and-read", "approved_resource_count=25", "environment_gate=aws-live-apply"),
        "rag-runtime-reviewed-recovery": ("approved_action=create-and-read", "approved_resource_count=18", "environment_gate=aws-live-apply"),
        "eks-runtime-backend-policy-update": ("approved_resource=aws_iam_policy.backend_runtime_access", "approved_action=update", "approved_changed_path=policy", "environment_gate=aws-live-apply"),
    }
    for contract, expected_values in expected_summary_branches.items():
        branch = summary_case.split(f"{contract})", 1)[1].split(";;", 1)[0]
        for value in expected_values:
            contains(branch, value)
    create_summary = summary_case.split("foundation-rag-apply-permission-create)", 1)[1].split(";;", 1)[0]
    update_summary = summary_case.split("foundation-rag-apply-permission-update)", 1)[1].split(";;", 1)[0]
    assert create_summary != update_summary
    assert "else" not in summary_case
    unknown_summary = summary_case.split("*)", 1)[1].split(";;", 1)[0]
    contains(unknown_summary, 'echo "unknown apply contract: ${APPLY_CONTRACT}" >&2')
    contains(unknown_summary, "exit 1")
    foundation = (ROOT / "infra/terraform/bootstrap/aws-live-foundation/main.tf").read_text(encoding="utf-8")
    for required in (
        "terraformers-dev-backend-irsa-role", "iam:PolicyARN", "Terraformers", "rag-runtime",
        "aoss:collection", "aoss:index", "terraformers-dev-refs/terraformers-reference-v1",
        "s3:PutEncryptionConfiguration",
        "CreateSecurityGroupsInApprovedVpc", "CreateTaggedRagSecurityGroups",
        "arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc/${var.rag_runtime_vpc_id}",
        "arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:security-group/*",
        "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
        "AWSServiceRoleForAmazonOpenSearchServerless", "observability.aoss.amazonaws.com",
        "arn:aws:codebuild:ap-northeast-2:${var.expected_aws_account_id}:project/terraformers-dev-refs-ingestion",
    ):
        contains(foundation, required)
    assert "s3:PutBucketEncryption" not in foundation
    vpc_statement = foundation.split('sid       = "CreateSecurityGroupsInApprovedVpc"', 1)[1].split('  statement {', 1)[0]
    tagged_sg_statement = foundation.split('sid       = "CreateTaggedRagSecurityGroups"', 1)[1].split('  statement {', 1)[0]
    assert "aws:RequestTag" not in vpc_statement
    for tag in ("aws:RequestTag/Project", "aws:RequestTag/Environment", "aws:RequestTag/Component"):
        contains(tagged_sg_statement, tag)
    for forbidden in (":role/terraformers-dev-refs-backend-aoss",):
        assert forbidden not in foundation, forbidden
    for forbidden in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
        assert forbidden not in apply, forbidden
    upload = apply.split("Upload sanitized apply evidence", 1)[1]
    for forbidden in ("live.tfplan", "live-plan.json", "live.auto.tfvars", "backend.hcl", "post-apply-plan.txt"):
        assert forbidden not in upload, forbidden


def fixture(address: str, resource_type: str, actions: list[str]) -> dict:
    return {"format_version": "1.2", "terraform_version": "1.15.8", "resource_changes": [{"address": address, "type": resource_type, "change": {"actions": actions, "before": None if actions == ["create"] else {"policy": "before"}, "after": {"name": address}}}]}


def verify_contract(plan: dict, contract: str, stage: str, success: bool, extra: list[str] | None = None, summary_success: bool = True) -> None:
    path = EVIDENCE_DIR / f"{contract}-{stage}.json"
    output = EVIDENCE_DIR / f"{contract}-{stage}-summary"
    path.write_text(json.dumps(plan), encoding="utf-8")
    run([sys.executable, str(SUMMARIZER), "--plan-json", str(path), "--output-dir", str(output), "--stage", stage], summary_success)
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


    foundation_permission = {"format_version": "1.2", "terraform_version": "1.15.8", "resource_changes": [{"address": "aws_iam_role_policy.terraform_apply_rag_runtime_create", "type": "aws_iam_role_policy", "change": {"actions": ["create"], "before": None, "after": {"name": "terraformers-live-apply-rag-runtime-create"}}}]}
    verify_contract(foundation_permission, "foundation-rag-apply-permission-create", "foundation", True)
    wrong_permission = json.loads(json.dumps(foundation_permission)); wrong_permission["resource_changes"][0]["address"] = "aws_iam_role_policy.unapproved"
    verify_contract(wrong_permission, "foundation-rag-apply-permission-create", "foundation", False)

    foundation_permission_update = json.loads(json.dumps(foundation_permission))
    foundation_permission_update["resource_changes"][0]["change"] = {"actions": ["update"], "before": {"policy": "before"}, "after": {"policy": "after"}}
    verify_contract(foundation_permission_update, "foundation-rag-apply-permission-update", "foundation", True)
    wrong_permission_update = json.loads(json.dumps(foundation_permission_update)); wrong_permission_update["resource_changes"][0]["address"] = "aws_iam_role_policy.unapproved"
    verify_contract(wrong_permission_update, "foundation-rag-apply-permission-update", "foundation", False)
    wrong_permission_path = json.loads(json.dumps(foundation_permission_update)); wrong_permission_path["resource_changes"][0]["change"]["after"] = {"name": "different", "policy": "after"}
    verify_contract(wrong_permission_path, "foundation-rag-apply-permission-update", "foundation", False)

    eks = fixture("aws_iam_policy.backend_runtime_access", "aws_iam_policy", ["update"])
    eks["resource_changes"][0]["change"]["after"] = {"policy": "after"}
    verify_contract(eks, "eks-runtime-backend-policy-update", "eks-runtime", True, ["--approved-resource", "aws_iam_policy.backend_runtime_access", "--approved-changed-path", "policy"])
    verify_contract(eks, "eks-runtime-backend-policy-update", "eks-runtime", False, ["--approved-resource", "aws_iam_policy.backend_runtime_access", "--approved-changed-path", "tags.Owner"])

    rag_changes = [
        {"address": address, "type": kind, "change": {"actions": ["create"], "before": None, "after": {"name": address}}}
        for address, kind in RAG_CREATES.items()
    ] + [
        {"address": address, "type": "aws_iam_policy_document", "change": {"actions": ["read"], "before": None, "after": {"json": "redacted"}}}
        for address in RAG_READS
    ]
    rag = {"format_version": "1.2", "terraform_version": "1.15.8", "resource_changes": rag_changes}
    verify_contract(rag, "rag-runtime-reviewed-create", "rag-runtime", True)
    extra_high_cost = json.loads(json.dumps(rag)); extra_high_cost["resource_changes"].append({"address": "aws_nat_gateway.extra", "type": "aws_nat_gateway", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(extra_high_cost, "rag-runtime-reviewed-create", "rag-runtime", False)
    extra = json.loads(json.dumps(rag)); extra["resource_changes"].append({"address": "aws_s3_bucket.extra", "type": "aws_s3_bucket", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(extra, "rag-runtime-reviewed-create", "rag-runtime", False)
    verify_contract({**rag, "resource_changes": rag_changes[:-1]}, "rag-runtime-reviewed-create", "rag-runtime", False)
    update = json.loads(json.dumps(rag)); update["resource_changes"][0]["change"] = {"actions": ["update"], "before": {"name": "old"}, "after": {"name": "new"}}
    verify_contract(update, "rag-runtime-reviewed-create", "rag-runtime", False)
    delete = json.loads(json.dumps(rag)); delete["resource_changes"][0]["change"] = {"actions": ["delete", "create"], "before": {"name": "old"}, "after": {"name": "new"}}
    verify_contract(delete, "rag-runtime-reviewed-create", "rag-runtime", False, summary_success=False)
    public = json.loads(json.dumps(rag)); public["resource_changes"][-1]["change"]["after"] = {"cidr_ipv4": "0.0.0.0/0"}
    public["resource_changes"][-1]["type"] = "aws_vpc_security_group_ingress_rule"
    verify_contract(public, "rag-runtime-reviewed-create", "rag-runtime", False, summary_success=False)
    unapproved_sg = json.loads(json.dumps(rag)); unapproved_sg["resource_changes"].append({"address": "aws_security_group.unapproved", "type": "aws_security_group", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(unapproved_sg, "rag-runtime-reviewed-create", "rag-runtime", False)


    recovery_changes = [
        {"address": address, "type": kind, "change": {"actions": ["create"], "before": None, "after": {"name": address}}}
        for address, kind in RAG_RECOVERY_CREATES.items()
    ] + [
        {"address": address, "type": "aws_iam_policy_document", "change": {"actions": ["read"], "before": None, "after": {"json": "redacted"}}}
        for address in RAG_READS
    ]
    recovery = {"format_version": "1.2", "terraform_version": "1.15.8", "resource_changes": recovery_changes}
    verify_contract(recovery, "rag-runtime-reviewed-recovery", "rag-runtime", True)
    recovery_existing = json.loads(json.dumps(recovery)); recovery_existing["resource_changes"].append(rag_changes[4])
    verify_contract(recovery_existing, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    verify_contract({**recovery, "resource_changes": recovery_changes[:-1]}, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_extra = json.loads(json.dumps(recovery)); recovery_extra["resource_changes"].append({"address": "aws_s3_bucket.extra", "type": "aws_s3_bucket", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(recovery_extra, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_update = json.loads(json.dumps(recovery)); recovery_update["resource_changes"][0]["change"] = {"actions": ["update"], "before": {"name": "old"}, "after": {"name": "new"}}
    verify_contract(recovery_update, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_delete = json.loads(json.dumps(recovery)); recovery_delete["resource_changes"][0]["change"] = {"actions": ["delete", "create"], "before": {"name": "old"}, "after": {"name": "new"}}
    verify_contract(recovery_delete, "rag-runtime-reviewed-recovery", "rag-runtime", False, summary_success=False)
    recovery_high_cost = json.loads(json.dumps(recovery)); recovery_high_cost["resource_changes"].append({"address": "aws_nat_gateway.extra", "type": "aws_nat_gateway", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(recovery_high_cost, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_unapproved_sg = json.loads(json.dumps(recovery)); recovery_unapproved_sg["resource_changes"].append({"address": "aws_security_group.unapproved", "type": "aws_security_group", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(recovery_unapproved_sg, "rag-runtime-reviewed-recovery", "rag-runtime", False)

    summary = [
        "approved_terraform_apply_contract_verification=passed",
        "foundation_positive_verification=passed", "foundation_negative_extra_resource=passed",
        "foundation_negative_missing_resource=passed", "foundation_negative_update=passed",
        "foundation_negative_wrong_address=passed", "foundation_permission_extension_positive_and_negative_verification=passed", "foundation_permission_update_positive_and_negative_verification=passed", "eks_runtime_positive_and_negative_verification=passed", "rag_runtime_positive_and_negative_verification=passed", "rag_runtime_recovery_positive_and_negative_verification=passed",
        "raw_plan_uploaded=false", "aws_mutation=none", "kubernetes_mutation=none",
    ]
    (EVIDENCE_DIR / "verification-summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print("\n".join(summary))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
