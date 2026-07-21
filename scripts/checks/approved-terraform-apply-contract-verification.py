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
    "aws_codebuild_project.corpus_ingestion": "aws_codebuild_project", "aws_iam_policy.backend_rag_runtime": "aws_iam_policy", "aws_iam_policy.codebuild_ingestion": "aws_iam_policy", "aws_iam_policy.corpus_ingestion": "aws_iam_policy", "aws_iam_role.codebuild_ingestion": "aws_iam_role", "aws_iam_role.corpus_ingestion": "aws_iam_role", "aws_iam_role_policy_attachment.backend_rag_runtime": "aws_iam_role_policy_attachment", "aws_iam_role_policy_attachment.codebuild_ingestion": "aws_iam_role_policy_attachment", "aws_iam_role_policy_attachment.corpus_ingestion": "aws_iam_role_policy_attachment", "aws_opensearchserverless_access_policy.data": "aws_opensearchserverless_access_policy", "aws_opensearchserverless_collection.references": "aws_opensearchserverless_collection", "aws_opensearchserverless_security_policy.encryption": "aws_opensearchserverless_security_policy", "aws_opensearchserverless_security_policy.network": "aws_opensearchserverless_security_policy", "aws_opensearchserverless_vpc_endpoint.collection": "aws_opensearchserverless_vpc_endpoint", "aws_s3_bucket.corpus": "aws_s3_bucket", "aws_s3_bucket_ownership_controls.corpus": "aws_s3_bucket_ownership_controls", "aws_s3_bucket_public_access_block.corpus": "aws_s3_bucket_public_access_block", "aws_s3_bucket_server_side_encryption_configuration.corpus": "aws_s3_bucket_server_side_encryption_configuration", "aws_s3_bucket_versioning.corpus": "aws_s3_bucket_versioning", "aws_security_group.aoss_vpc_endpoint": "aws_security_group", "aws_security_group.codebuild_ingestion": "aws_security_group", "aws_vpc_security_group_ingress_rule.aoss_from_backend": "aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_ingress_rule.aoss_from_codebuild": "aws_vpc_security_group_ingress_rule",
}
RAG_READS = ("data.aws_iam_policy_document.backend_rag_runtime", "data.aws_iam_policy_document.codebuild_ingestion", "data.aws_iam_policy_document.corpus_ingestion")
FOUNDATION = {
    "aws_iam_role.terraform_apply": "aws_iam_role",
    "aws_iam_role_policy.terraform_apply_iam_mutation": "aws_iam_role_policy",
    "aws_iam_role_policy.terraform_apply_state_access": "aws_iam_role_policy",
    "aws_iam_role_policy_attachment.terraform_apply_read_only": "aws_iam_role_policy_attachment",
}
OPERATIONS_VISIBILITY = {
    "aws_cloudwatch_dashboard.operations_visibility": "aws_cloudwatch_dashboard",
    "aws_cloudwatch_metric_alarm.analysis_failure": "aws_cloudwatch_metric_alarm",
    "aws_cloudwatch_metric_alarm.backend_fault": "aws_cloudwatch_metric_alarm",
    "aws_cloudwatch_metric_alarm.backend_unavailable": "aws_cloudwatch_metric_alarm",
    "aws_eks_addon.cloudwatch_observability": "aws_eks_addon",
    "aws_iam_role.cloudwatch_observability_irsa": "aws_iam_role",
    "aws_iam_role_policy.backend_cloudwatch_metrics": "aws_iam_role_policy",
    "aws_iam_role_policy_attachment.cloudwatch_observability_agent": "aws_iam_role_policy_attachment",
    "aws_iam_role_policy_attachment.cloudwatch_observability_xray": "aws_iam_role_policy_attachment",
}
OPERATIONS_VISIBILITY_PERMISSION = {
    "aws_iam_policy.terraform_apply_operations_visibility_create": "aws_iam_policy",
    "aws_iam_role_policy_attachment.terraform_apply_operations_visibility_create": "aws_iam_role_policy_attachment",
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
        "APPLY_REVIEWED_FOUNDATION_CREATE", "APPLY_REVIEWED_RAG_APPLY_PERMISSION_CREATE", "APPLY_REVIEWED_RAG_APPLY_PERMISSION_UPDATE", "APPLY_REVIEWED_OPERATIONS_VISIBILITY_APPLY_PERMISSION_CREATE", "foundation-rag-apply-permission-create", "foundation-rag-apply-permission-update", "foundation-operations-visibility-apply-permission-create", "APPLY_REVIEWED_IN_PLACE_UPDATE", "APPLY_REVIEWED_OPERATIONS_VISIBILITY_CREATE", "eks-runtime-operations-visibility-create", "APPLY_REVIEWED_OPERATIONS_VISIBILITY_ADDON_RECOVERY", "eks-runtime-operations-visibility-addon-recovery", "APPLY_REVIEWED_RAG_RUNTIME_CREATE", "APPLY_REVIEWED_RAG_RUNTIME_RECOVERY", "rag-runtime-reviewed-create", "rag-runtime-reviewed-recovery",
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
        "foundation-operations-visibility-apply-permission-create": (
            "approved_action=create", "approved_resource=aws_iam_policy.terraform_apply_operations_visibility_create",
            "approved_resource=aws_iam_role_policy_attachment.terraform_apply_operations_visibility_create",
            "approved_resource_count=2", "environment_gate=aws-live-plan",
            "temporary_bootstrap_permission_cleanup=external-required",
        ),
        "rag-runtime-reviewed-create": ("approved_action=create-and-read", "approved_resource_count=26", "environment_gate=aws-live-apply"),
        "rag-runtime-reviewed-recovery": ("approved_action=create-and-read", "approved_resource_count=${approved_resource_count}", "environment_gate=aws-live-apply"),
        "eks-runtime-backend-policy-update": ("approved_resource=aws_iam_policy.backend_runtime_access", "approved_action=update", "approved_changed_path=policy", "environment_gate=aws-live-apply"),
        "eks-runtime-operations-visibility-create": ("approved_action=create", "approved_resource_count=9", "environment_gate=aws-live-apply"),
        "eks-runtime-operations-visibility-addon-recovery": ("approved_action=create", "approved_resource=aws_eks_addon.cloudwatch_observability", "approved_resource_count=1", "environment_gate=aws-live-apply"),
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
        "CreateExactCollectionAossAccessPolicy", "CreateExactIndexAossAccessPolicy",
        "aoss:collection", "aoss:index", "terraformers-dev-refs/terraformers-reference-v1",
        "s3:PutEncryptionConfiguration",
        "CreateSecurityGroupsInApprovedVpc", "CreateTaggedRagSecurityGroups",
        "arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc/${var.rag_runtime_vpc_id}",
        "arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:security-group/*",
        "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
        "AWSServiceRoleForAmazonOpenSearchServerless", "observability.aoss.amazonaws.com",
        "arn:aws:codebuild:ap-northeast-2:${var.expected_aws_account_id}:project/terraformers-dev-refs-ingestion",
        "aoss:CreateVpcEndpoint", "ec2:CreateVpcEndpoint", "ec2:CreateTags",
        "ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint", "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets", "ec2:DescribeVpcEndpoints", "ec2:DescribeVpcs",
        "arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc/${var.rag_runtime_vpc_id}",
        "arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc-endpoint/*",
        "ec2:CreateAction",
        "CreateVpcEndpoint", "route53:AssociateVPCWithHostedZone",
        "route53:ChangeResourceRecordSets", "route53:CreateHostedZone",
        "route53:DeleteHostedZone", "route53:GetChange", "route53:GetHostedZone",
        "route53:ListHostedZonesByName", "route53:ListHostedZonesByVPC",
        "route53:ListResourceRecordSets", "route53:VPCs",
    ):
        contains(foundation, required)
    assert "s3:PutBucketEncryption" not in foundation
    for forbidden in ("AdministratorAccess", "AmazonEC2FullAccess", "AmazonRoute53FullAccess"):
        assert forbidden not in foundation, forbidden
    create_vpc_endpoint_statements = {
        sid: foundation.split(f'sid       = "{sid}"', 1)[1].split('  statement {', 1)[0]
        for sid in (
            "CreateAossManagedVpcEndpointInApprovedVpc",
            "CreateAossManagedVpcEndpointInApprovedSubnets",
            "CreateAossManagedVpcEndpointWithTaggedSecurityGroups",
            "CreateAossManagedVpcEndpoint",
        )
    }
    for sid in (
        "CreateAossManagedVpcEndpointInApprovedVpc",
        "CreateAossManagedVpcEndpointInApprovedSubnets",
        "CreateAossManagedVpcEndpointWithTaggedSecurityGroups",
    ):
        assert "ec2:VpceServiceName" not in create_vpc_endpoint_statements[sid], sid
    endpoint_statement = create_vpc_endpoint_statements["CreateAossManagedVpcEndpoint"]
    contains(endpoint_statement, 'resources = ["arn:aws:ec2:ap-northeast-2:${var.expected_aws_account_id}:vpc-endpoint/*"]')
    assert "ec2:VpceServiceName" not in endpoint_statement
    assert "com.amazonaws.ap-northeast-2.aoss" not in endpoint_statement
    route53_vpc_value = 'values   = ["VPCId=${var.rag_runtime_vpc_id},VPCRegion=ap-northeast-2"]'
    for sid, resource in (
        ("CreateAossPrivateHostedZone", 'resources = ["*"]'),
        ("AssociateAossVpcWithPrivateHostedZone", 'resources = ["arn:aws:route53:::hostedzone/*"]'),
        ("ListAossPrivateDnsZonesByVpc", 'resources = ["*"]'),
    ):
        statement = foundation.split(f'sid       = "{sid}"', 1)[1].split('  statement {', 1)[0]
        contains(statement, resource)
        contains(statement, 'test     = "ForAllValues:StringEquals"')
        contains(statement, 'variable = "route53:VPCs"')
        contains(statement, route53_vpc_value)
        assert "ArnEquals" not in statement
        assert "arn:aws:ec2:" not in statement
    collection_access_policy_statement = foundation.split('sid       = "CreateExactCollectionAossAccessPolicy"', 1)[1].split('  statement {', 1)[0]
    index_access_policy_statement = foundation.split('sid       = "CreateExactIndexAossAccessPolicy"', 1)[1].split('  statement {', 1)[0]
    for statement in (collection_access_policy_statement, index_access_policy_statement):
        contains(statement, 'actions   = ["aoss:CreateAccessPolicy"]')
        contains(statement, 'resources = ["*"]')
        contains(statement, 'test     = "StringEquals"')
    contains(collection_access_policy_statement, 'variable = "aoss:collection"')
    contains(collection_access_policy_statement, 'values   = ["terraformers-dev-refs"]')
    assert 'aoss:index' not in collection_access_policy_statement
    contains(index_access_policy_statement, 'variable = "aoss:index"')
    contains(index_access_policy_statement, 'values   = ["terraformers-dev-refs/terraformers-reference-v1"]')
    assert 'aoss:collection' not in index_access_policy_statement
    assert 'sid       = "CreateExactAossAccessPolicy"' not in foundation
    cloudwatch_attach_statement = foundation.split('sid       = "AttachApprovedCloudWatchManagedPolicies"', 1)[1].split('  statement {', 1)[0]
    contains(cloudwatch_attach_statement, 'test     = "ArnEquals"')
    contains(cloudwatch_attach_statement, 'variable = "iam:PolicyARN"')
    contains(cloudwatch_attach_statement, 'arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy')
    contains(cloudwatch_attach_statement, 'arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess')
    assert 'ForAnyValue:StringEquals' not in cloudwatch_attach_statement
    vpc_statement = foundation.split('sid       = "CreateSecurityGroupsInApprovedVpc"', 1)[1].split('  statement {', 1)[0]
    tagged_sg_statement = foundation.split('sid       = "CreateTaggedRagSecurityGroups"', 1)[1].split('  statement {', 1)[0]
    assert "aws:RequestTag" not in vpc_statement
    for tag in ("aws:RequestTag/Project", "aws:RequestTag/Environment", "aws:RequestTag/Component"):
        contains(tagged_sg_statement, tag)
    for forbidden in (":role/terraformers-dev-refs-backend-aoss",):
        assert forbidden not in foundation, forbidden
    operations_visibility_policy = foundation.split('resource "aws_iam_policy" "terraform_apply_operations_visibility_create" {', 1)[1].split("\n}\n", 1)[0]
    contains(operations_visibility_policy, 'name   = "terraformers-live-apply-operations-visibility-create"')
    contains(operations_visibility_policy, "policy = data.aws_iam_policy_document.terraform_apply_operations_visibility_create.json")
    contains(operations_visibility_policy, "tags   = var.common_tags")
    operations_visibility_attachment = foundation.split('resource "aws_iam_role_policy_attachment" "terraform_apply_operations_visibility_create" {', 1)[1].split("\n}\n", 1)[0]
    contains(operations_visibility_attachment, "role       = aws_iam_role.terraform_apply.name")
    contains(operations_visibility_attachment, "policy_arn = aws_iam_policy.terraform_apply_operations_visibility_create.arn")
    assert 'resource "aws_iam_role_policy" "terraform_apply_operations_visibility_create" {' not in foundation
    for forbidden in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
        assert forbidden not in apply, forbidden
    upload = apply.split("Upload sanitized apply evidence", 1)[1]
    for forbidden in ("live.tfplan", "live-plan.json", "live.auto.tfvars", "backend.hcl", "post-apply-plan.txt"):
        assert forbidden not in upload, forbidden

    rag_main = (ROOT / "infra/terraform/envs/rag-runtime/main.tf").read_text(encoding="utf-8")
    aoss_security_group = rag_main.split('resource "aws_security_group" "aoss_vpc_endpoint" {', 1)[1].split("\n}\n", 1)[0]
    assert "ingress {" not in aoss_security_group
    contains(aoss_security_group, "ingress = []")
    backend_rule = rag_main.split('resource "aws_vpc_security_group_ingress_rule" "aoss_from_backend" {', 1)[1].split("\n}\n", 1)[0]
    codebuild_rule = rag_main.split('resource "aws_vpc_security_group_ingress_rule" "aoss_from_codebuild" {', 1)[1].split("\n}\n", 1)[0]
    for rule in (backend_rule, codebuild_rule):
        contains(rule, "from_port                    = 443")
        contains(rule, "to_port                      = 443")
        contains(rule, 'ip_protocol                  = "tcp"')
        assert "0.0.0.0/0" not in rule
    contains(backend_rule, "referenced_security_group_id = var.eks_cluster_primary_security_group_id")
    contains(codebuild_rule, "referenced_security_group_id = aws_security_group.codebuild_ingestion.id")


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

    operations_visibility_permission_changes = [
        {"address": address, "type": kind, "change": {"actions": ["create"], "before": None, "after": {"name": address}}}
        for address, kind in OPERATIONS_VISIBILITY_PERMISSION.items()
    ]
    operations_visibility_permission = {"format_version": "1.2", "terraform_version": "1.15.8", "resource_changes": operations_visibility_permission_changes}
    verify_contract(operations_visibility_permission, "foundation-operations-visibility-apply-permission-create", "foundation", True)
    old_inline_operations_visibility_permission = {"format_version": "1.2", "terraform_version": "1.15.8", "resource_changes": [{"address": "aws_iam_role_policy.terraform_apply_operations_visibility_create", "type": "aws_iam_role_policy", "change": {"actions": ["create"], "before": None, "after": {"name": "terraformers-live-apply-operations-visibility-create"}}}]}
    verify_contract(old_inline_operations_visibility_permission, "foundation-operations-visibility-apply-permission-create", "foundation", False)
    policy_only_operations_visibility_permission = json.loads(json.dumps(operations_visibility_permission)); policy_only_operations_visibility_permission["resource_changes"] = policy_only_operations_visibility_permission["resource_changes"][:1]
    verify_contract(policy_only_operations_visibility_permission, "foundation-operations-visibility-apply-permission-create", "foundation", False)
    attachment_only_operations_visibility_permission = json.loads(json.dumps(operations_visibility_permission)); attachment_only_operations_visibility_permission["resource_changes"] = attachment_only_operations_visibility_permission["resource_changes"][1:]
    verify_contract(attachment_only_operations_visibility_permission, "foundation-operations-visibility-apply-permission-create", "foundation", False)
    extra_operations_visibility_permission = json.loads(json.dumps(operations_visibility_permission)); extra_operations_visibility_permission["resource_changes"].append({"address": "aws_iam_policy.extra", "type": "aws_iam_policy", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(extra_operations_visibility_permission, "foundation-operations-visibility-apply-permission-create", "foundation", False)
    wrong_operations_visibility_permission = json.loads(json.dumps(operations_visibility_permission)); wrong_operations_visibility_permission["resource_changes"][0]["address"] = "aws_iam_policy.unapproved"
    verify_contract(wrong_operations_visibility_permission, "foundation-operations-visibility-apply-permission-create", "foundation", False)
    wrong_operations_visibility_permission_type = json.loads(json.dumps(operations_visibility_permission)); wrong_operations_visibility_permission_type["resource_changes"][0]["type"] = "aws_iam_role_policy"
    verify_contract(wrong_operations_visibility_permission_type, "foundation-operations-visibility-apply-permission-create", "foundation", False)
    for action in (["update"], ["delete"], ["delete", "create"]):
        changed_operations_visibility_permission = json.loads(json.dumps(operations_visibility_permission)); changed_operations_visibility_permission["resource_changes"][0]["change"] = {"actions": action, "before": {"name": "before"}, "after": {"name": "after"}}
        verify_contract(changed_operations_visibility_permission, "foundation-operations-visibility-apply-permission-create", "foundation", False, summary_success=action == ["update"])

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

    operations_visibility_changes = [
        {"address": address, "type": kind, "change": {"actions": ["create"], "before": None, "after": {"name": address}}}
        for address, kind in OPERATIONS_VISIBILITY.items()
    ]
    operations_visibility = {"format_version": "1.2", "terraform_version": "1.15.8", "resource_changes": operations_visibility_changes}
    verify_contract(operations_visibility, "eks-runtime-operations-visibility-create", "eks-runtime", True)
    operations_visibility_extra = json.loads(json.dumps(operations_visibility)); operations_visibility_extra["resource_changes"].append({"address": "aws_iam_role_policy.extra", "type": "aws_iam_role_policy", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(operations_visibility_extra, "eks-runtime-operations-visibility-create", "eks-runtime", False)
    operations_visibility_node_group = json.loads(json.dumps(operations_visibility)); operations_visibility_node_group["resource_changes"][0] = {"address": "aws_eks_node_group.backend", "type": "aws_eks_node_group", "change": {"actions": ["create"], "before": None, "after": {"name": "backend"}}}
    verify_contract(operations_visibility_node_group, "eks-runtime-operations-visibility-create", "eks-runtime", False)

    operations_visibility_addon_recovery = fixture("aws_eks_addon.cloudwatch_observability", "aws_eks_addon", ["create"])
    verify_contract(operations_visibility_addon_recovery, "eks-runtime-operations-visibility-addon-recovery", "eks-runtime", True)
    addon_recovery_dashboard = fixture("aws_cloudwatch_dashboard.operations_visibility", "aws_cloudwatch_dashboard", ["create"])
    verify_contract(addon_recovery_dashboard, "eks-runtime-operations-visibility-addon-recovery", "eks-runtime", False)
    addon_recovery_extra = json.loads(json.dumps(operations_visibility_addon_recovery)); addon_recovery_extra["resource_changes"].append({"address": "aws_iam_role.extra", "type": "aws_iam_role", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(addon_recovery_extra, "eks-runtime-operations-visibility-addon-recovery", "eks-runtime", False)
    addon_recovery_wrong_type = json.loads(json.dumps(operations_visibility_addon_recovery)); addon_recovery_wrong_type["resource_changes"][0]["type"] = "aws_cloudwatch_dashboard"
    verify_contract(addon_recovery_wrong_type, "eks-runtime-operations-visibility-addon-recovery", "eks-runtime", False)
    for action in (["update"], ["delete"], ["delete", "create"]):
        addon_recovery_changed = json.loads(json.dumps(operations_visibility_addon_recovery)); addon_recovery_changed["resource_changes"][0]["change"] = {"actions": action, "before": {"name": "before"}, "after": {"name": "after"}}
        verify_contract(addon_recovery_changed, "eks-runtime-operations-visibility-addon-recovery", "eks-runtime", False, summary_success=action == ["update"])
    verify_contract({**operations_visibility_addon_recovery, "resource_changes": []}, "eks-runtime-operations-visibility-addon-recovery", "eks-runtime", False)
    addon_recovery_count_mismatch = json.loads(json.dumps(operations_visibility_addon_recovery)); addon_recovery_count_mismatch["resource_changes"].append({"address": "aws_iam_role.extra", "type": "aws_iam_role", "change": {"actions": ["read"], "before": None, "after": {"name": "extra"}}})
    verify_contract(addon_recovery_count_mismatch, "eks-runtime-operations-visibility-addon-recovery", "eks-runtime", False)
    verify_contract(operations_visibility_addon_recovery, "eks-runtime-operations-visibility-addon-recovery", "foundation", False)

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
        {"address": "aws_opensearchserverless_collection.references", "type": "aws_opensearchserverless_collection", "change": {"actions": ["create"], "before": None, "after": {"name": "references"}}},
        {"address": "aws_opensearchserverless_vpc_endpoint.collection", "type": "aws_opensearchserverless_vpc_endpoint", "change": {"actions": ["create"], "before": None, "after": {"name": "collection"}}},
        {"address": RAG_READS[0], "type": "aws_iam_policy_document", "change": {"actions": ["read"], "before": None, "after": {"json": "redacted"}}},
    ]
    recovery = {"format_version": "1.2", "terraform_version": "1.15.8", "resource_changes": recovery_changes}
    verify_contract(recovery, "rag-runtime-reviewed-recovery", "rag-runtime", True)
    recovery_existing = {**recovery, "resource_changes": [recovery_changes[1], recovery_changes[2]]}
    verify_contract(recovery_existing, "rag-runtime-reviewed-recovery", "rag-runtime", True)
    recovery_migration = json.loads(json.dumps(recovery))
    recovery_migration["resource_changes"].append({"address": "aws_security_group.aoss_vpc_endpoint", "type": "aws_security_group", "change": {"actions": ["update"], "before": {"ingress": [{"from_port": 443}]}, "after": {"ingress": []}}})
    verify_contract(recovery_migration, "rag-runtime-reviewed-recovery", "rag-runtime", True)
    recovery_extra = json.loads(json.dumps(recovery)); recovery_extra["resource_changes"].append({"address": "aws_s3_bucket.extra", "type": "aws_s3_bucket", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(recovery_extra, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_update = json.loads(json.dumps(recovery)); recovery_update["resource_changes"][0]["change"] = {"actions": ["update"], "before": {"name": "old"}, "after": {"name": "new"}}
    verify_contract(recovery_update, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_other_sg_update = json.loads(json.dumps(recovery_migration)); recovery_other_sg_update["resource_changes"][-1]["address"] = "aws_security_group.codebuild_ingestion"
    verify_contract(recovery_other_sg_update, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    for attribute in ("tags", "description", "egress"):
        recovery_wrong_migration_path = json.loads(json.dumps(recovery_migration))
        recovery_wrong_migration_path["resource_changes"][-1]["change"] = {"actions": ["update"], "before": {attribute: "before"}, "after": {attribute: "after"}}
        verify_contract(recovery_wrong_migration_path, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_multiple_migration_paths = json.loads(json.dumps(recovery_migration))
    recovery_multiple_migration_paths["resource_changes"][-1]["change"] = {"actions": ["update"], "before": {"ingress": [], "description": "before"}, "after": {"ingress": [{"from_port": 443}], "description": "after"}}
    verify_contract(recovery_multiple_migration_paths, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_two_updates = json.loads(json.dumps(recovery_migration)); recovery_two_updates["resource_changes"].append({"address": "aws_security_group.codebuild_ingestion", "type": "aws_security_group", "change": {"actions": ["update"], "before": {"description": "before"}, "after": {"description": "after"}}})
    verify_contract(recovery_two_updates, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_delete = json.loads(json.dumps(recovery)); recovery_delete["resource_changes"][0]["change"] = {"actions": ["delete", "create"], "before": {"name": "old"}, "after": {"name": "new"}}
    verify_contract(recovery_delete, "rag-runtime-reviewed-recovery", "rag-runtime", False, summary_success=False)
    recovery_high_cost = json.loads(json.dumps(recovery)); recovery_high_cost["resource_changes"].append({"address": "aws_nat_gateway.extra", "type": "aws_nat_gateway", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(recovery_high_cost, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_unapproved_sg = json.loads(json.dumps(recovery)); recovery_unapproved_sg["resource_changes"].append({"address": "aws_security_group.unapproved", "type": "aws_security_group", "change": {"actions": ["create"], "before": None, "after": {"name": "extra"}}})
    verify_contract(recovery_unapproved_sg, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_managed_read = json.loads(json.dumps(recovery)); recovery_managed_read["resource_changes"][0]["change"]["actions"] = ["read"]
    verify_contract(recovery_managed_read, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_data_create = json.loads(json.dumps(recovery)); recovery_data_create["resource_changes"][-1]["change"]["actions"] = ["create"]
    verify_contract(recovery_data_create, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_no_create = {**recovery, "resource_changes": [recovery_changes[-1]]}
    verify_contract(recovery_no_create, "rag-runtime-reviewed-recovery", "rag-runtime", False)
    recovery_public = json.loads(json.dumps(recovery)); recovery_public["resource_changes"].append({"address": "aws_vpc_security_group_ingress_rule.aoss_from_codebuild", "type": "aws_vpc_security_group_ingress_rule", "change": {"actions": ["create"], "before": None, "after": {"cidr_ipv4": "0.0.0.0/0"}}})
    verify_contract(recovery_public, "rag-runtime-reviewed-recovery", "rag-runtime", False, summary_success=False)

    summary = [
        "approved_terraform_apply_contract_verification=passed",
        "foundation_positive_verification=passed", "foundation_negative_extra_resource=passed",
        "foundation_negative_missing_resource=passed", "foundation_negative_update=passed",
        "foundation_negative_wrong_address=passed", "foundation_permission_extension_positive_and_negative_verification=passed", "foundation_operations_visibility_permission_positive_and_negative_verification=passed", "foundation_permission_update_positive_and_negative_verification=passed", "eks_runtime_positive_and_negative_verification=passed", "operations_visibility_positive_and_negative_verification=passed", "operations_visibility_addon_recovery_positive_and_negative_verification=passed", "rag_runtime_positive_and_negative_verification=passed", "rag_runtime_recovery_positive_and_negative_verification=passed",
        "raw_plan_uploaded=false", "aws_mutation=none", "kubernetes_mutation=none",
    ]
    (EVIDENCE_DIR / "verification-summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print("\n".join(summary))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
