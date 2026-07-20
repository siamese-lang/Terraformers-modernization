#!/usr/bin/env bash

fail() {
  echo "$1" >&2
  exit 1
}

BRANCH="$(git branch --show-current)"
[[ "$BRANCH" == "agent/fix-rag-recovery-vpce-permission" ]] || fail "BRANCH_MISMATCH: $BRANCH"

git diff --quiet -- infra/terraform/bootstrap/aws-live-foundation/main.tf \
  infra/terraform/envs/rag-runtime/main.tf \
  scripts/checks/approved-terraform-apply-contract-verification.py \
  || fail "TARGET_FILES_ALREADY_MODIFIED"

FOUNDATION="infra/terraform/bootstrap/aws-live-foundation/main.tf"
RAG="infra/terraform/envs/rag-runtime/main.tf"
CHECK="scripts/checks/approved-terraform-apply-contract-verification.py"

[[ "$(grep -c 'variable = "ec2:VpceServiceName"' "$FOUNDATION")" == "1" ]] \
  || fail "FOUNDATION_PRECONDITION_FAILED"
[[ "$(grep -c '^  ingress = \[\]$' "$RAG")" == "0" ]] \
  || fail "RAG_PRECONDITION_FAILED"
[[ "$(grep -c 'contains(endpoint_statement,.*StringLike' "$CHECK")" == "1" ]] \
  || fail "CHECK_PRECONDITION_FAILED"

awk '
BEGIN { in_target = 0; skipping = 0; removed = 0 }
{
  if (index($0, "sid       = \"CreateAossManagedVpcEndpoint\"") > 0) {
    in_target = 1
  }

  if (in_target && !skipping && $0 == "    condition {") {
    skipping = 1
    removed++
    next
  }

  if (skipping) {
    if ($0 == "    }") {
      skipping = 0
    }
    next
  }

  print

  if (in_target && $0 == "  }") {
    in_target = 0
  }
}
END {
  if (removed != 1) {
    exit 42
  }
}
' "$FOUNDATION" > "${FOUNDATION}.tmp" || fail "FOUNDATION_EDIT_FAILED"
mv "${FOUNDATION}.tmp" "$FOUNDATION" || fail "FOUNDATION_MOVE_FAILED"

awk '
BEGIN { in_target = 0; inserted = 0 }
{
  if ($0 == "resource \"aws_security_group\" \"aoss_vpc_endpoint\" {") {
    in_target = 1
  }

  if (in_target && $0 == "  vpc_id      = var.vpc_id") {
    print
    print ""
    print "  ingress = []"
    inserted++
    next
  }

  print

  if (in_target && $0 == "}") {
    in_target = 0
  }
}
END {
  if (inserted != 1) {
    exit 42
  }
}
' "$RAG" > "${RAG}.tmp" || fail "RAG_EDIT_FAILED"
mv "${RAG}.tmp" "$RAG" || fail "RAG_MOVE_FAILED"

awk '
BEGIN { required_changed = 0; endpoint_changed = 0; ingress_added = 0; skip = 0 }
{
  if (skip > 0) {
    skip--
    next
  }

  if (index($0, "\"ec2:VpceServiceName\", \"com.amazonaws.ap-northeast-2.aoss*\", \"ec2:CreateAction\",") > 0) {
    print "        \"ec2:CreateAction\","
    required_changed++
    next
  }

  if (index($0, "contains(endpoint_statement,") > 0 && index($0, "StringLike") > 0) {
    print "    assert \"ec2:VpceServiceName\" not in endpoint_statement"
    print "    assert \"com.amazonaws.ap-northeast-2.aoss\" not in endpoint_statement"
    endpoint_changed++
    skip = 2
    next
  }

  print

  if ($0 == "    assert \"ingress {\" not in aoss_security_group") {
    print "    contains(aoss_security_group, \"ingress = []\")"
    ingress_added++
  }
}
END {
  if (required_changed != 1 || endpoint_changed != 1 || ingress_added != 1) {
    exit 42
  }
}
' "$CHECK" > "${CHECK}.tmp" || fail "CHECK_EDIT_FAILED"
mv "${CHECK}.tmp" "$CHECK" || fail "CHECK_MOVE_FAILED"

[[ "$(grep -c 'variable = "ec2:VpceServiceName"' "$FOUNDATION")" == "0" ]] \
  || fail "FOUNDATION_POSTCONDITION_FAILED"
[[ "$(grep -c '^  ingress = \[\]$' "$RAG")" == "1" ]] \
  || fail "RAG_POSTCONDITION_FAILED"
[[ "$(grep -c 'assert "ec2:VpceServiceName" not in endpoint_statement' "$CHECK")" == "1" ]] \
  || fail "CHECK_POSTCONDITION_FAILED"

git diff --check || fail "DIFF_CHECK_FAILED"

git rm -f \
  scripts/deploy/rag-recovery-blockers.patch \
  scripts/deploy/apply-rag-recovery-blockers-fix.sh \
  >/dev/null || fail "TEMP_FILE_CLEANUP_FAILED"

echo "RAG_RECOVERY_BLOCKERS_FIXED"
git status --short
