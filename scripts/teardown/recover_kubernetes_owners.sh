#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:?output directory is required}"
REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER="${EKS_CLUSTER_NAME:-terraformers-dev-backend}"
STATE_BUCKET="${STATE_BUCKET:?STATE_BUCKET is required}"
STATE_PREFIX="${STATE_PREFIX:?STATE_PREFIX is required}"
RUN_DIR="${RUNNER_TEMP:-/tmp}/terraformers-kubernetes-owner-recovery"
MARKER_FILE="${RUN_DIR}/kubernetes-owners.json"
LB_FILE="${RUN_DIR}/load-balancers.txt"
TG_FILE="${RUN_DIR}/target-groups.txt"

mkdir -p "$OUTPUT_DIR" "$RUN_DIR"
: > "$LB_FILE"
: > "$TG_FILE"

resource_matches_project() {
  local arn="$1"
  local name="$2"
  local tags_file="${RUN_DIR}/tags.json"

  if [[ "${name,,}" == *terraformers* ]]; then
    return 0
  fi

  aws elbv2 describe-tags \
    --region "$REGION" \
    --resource-arns "$arn" \
    --output json > "$tags_file"

  jq -e --arg cluster "$CLUSTER" '
    any(.TagDescriptions[0].Tags[]?;
      (.Key == "elbv2.k8s.aws/cluster" and .Value == $cluster)
      or (.Key == ("kubernetes.io/cluster/" + $cluster))
      or (
        ((.Key // "") | ascii_downcase) == "project"
        and ((.Value // "") | ascii_downcase | contains("terraformers"))
      )
    )
  ' "$tags_file" >/dev/null
}

collect_project_load_balancers() {
  local output_file="$1"
  local inventory="${RUN_DIR}/load-balancer-inventory.json"
  : > "$output_file"

  aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --output json > "$inventory"

  while IFS=$'\t' read -r arn name; do
    [ -n "$arn" ] || continue
    if resource_matches_project "$arn" "$name"; then
      printf '%s\n' "$arn" >> "$output_file"
    fi
  done < <(jq -r '.LoadBalancers[]? | [.LoadBalancerArn, .LoadBalancerName] | @tsv' "$inventory")
}

collect_project_target_groups() {
  local output_file="$1"
  local inventory="${RUN_DIR}/target-group-inventory.json"
  : > "$output_file"

  aws elbv2 describe-target-groups \
    --region "$REGION" \
    --output json > "$inventory"

  while IFS=$'\t' read -r arn name; do
    [ -n "$arn" ] || continue
    if resource_matches_project "$arn" "$name"; then
      printf '%s\n' "$arn" >> "$output_file"
    fi
  done < <(jq -r '.TargetGroups[]? | [.TargetGroupArn, .TargetGroupName] | @tsv' "$inventory")
}

wait_for_load_balancer_absence() {
  local arn="$1"
  local error_file="${RUN_DIR}/load-balancer-error.txt"

  for attempt in $(seq 1 40); do
    if aws elbv2 describe-load-balancers \
      --region "$REGION" \
      --load-balancer-arns "$arn" \
      >/dev/null 2>"$error_file"; then
      sleep 15
      continue
    fi

    if grep -q 'LoadBalancerNotFound' "$error_file"; then
      return 0
    fi

    echo 'Unable to verify load balancer deletion.' >&2
    return 1
  done

  echo 'Project load balancer deletion did not complete within the bounded wait.' >&2
  return 1
}

wait_for_target_group_absence() {
  local arn="$1"
  local error_file="${RUN_DIR}/target-group-error.txt"

  for attempt in $(seq 1 40); do
    if aws elbv2 describe-target-groups \
      --region "$REGION" \
      --target-group-arns "$arn" \
      >/dev/null 2>"$error_file"; then
      sleep 15
      continue
    fi

    if grep -q 'TargetGroupNotFound' "$error_file"; then
      return 0
    fi

    echo 'Unable to verify target group deletion.' >&2
    return 1
  done

  echo 'Project target group deletion did not complete within the bounded wait.' >&2
  return 1
}

collect_project_load_balancers "$LB_FILE"
load_balancer_delete_count="$(grep -c . "$LB_FILE" || true)"

while IFS= read -r arn; do
  [ -n "$arn" ] || continue
  aws elbv2 delete-load-balancer \
    --region "$REGION" \
    --load-balancer-arn "$arn"
done < "$LB_FILE"

while IFS= read -r arn; do
  [ -n "$arn" ] || continue
  wait_for_load_balancer_absence "$arn"
done < "$LB_FILE"

collect_project_target_groups "$TG_FILE"
target_group_delete_count="$(grep -c . "$TG_FILE" || true)"

while IFS= read -r arn; do
  [ -n "$arn" ] || continue
  deleted=false
  for attempt in $(seq 1 40); do
    error_file="${RUN_DIR}/target-group-delete-error.txt"
    if aws elbv2 delete-target-group \
      --region "$REGION" \
      --target-group-arn "$arn" \
      >/dev/null 2>"$error_file"; then
      deleted=true
      break
    fi
    if grep -q 'ResourceInUse' "$error_file"; then
      sleep 15
      continue
    fi
    echo 'Project target group deletion failed.' >&2
    exit 1
  done
  if [ "$deleted" != true ]; then
    echo 'Project target group remained in use after the bounded retry.' >&2
    exit 1
  fi
done < "$TG_FILE"

while IFS= read -r arn; do
  [ -n "$arn" ] || continue
  wait_for_target_group_absence "$arn"
done < "$TG_FILE"

collect_project_load_balancers "${RUN_DIR}/load-balancers-after.txt"
collect_project_target_groups "${RUN_DIR}/target-groups-after.txt"
load_balancer_remaining="$(grep -c . "${RUN_DIR}/load-balancers-after.txt" || true)"
target_group_remaining="$(grep -c . "${RUN_DIR}/target-groups-after.txt" || true)"

if [ "$load_balancer_remaining" -ne 0 ] || [ "$target_group_remaining" -ne 0 ]; then
  echo "Project ELB residuals remain: load_balancers=${load_balancer_remaining},target_groups=${target_group_remaining}" >&2
  exit 1
fi

jq -n \
  --arg commit "${GITHUB_SHA:-}" \
  --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    stage:"kubernetes-owners",
    source_commit:$commit,
    completed_at:$completed_at,
    owners_removed:true,
    cleanup_mode:"direct-aws-external-owners"
  }' > "$MARKER_FILE"

aws s3api put-object \
  --bucket "$STATE_BUCKET" \
  --key "${STATE_PREFIX%/}/closure/kubernetes-owners.json" \
  --body "$MARKER_FILE" >/dev/null

{
  echo 'kubernetes_external_owners_removed=true'
  echo 'in_cluster_resources_deferred_to_eks_destroy=true'
  echo "load_balancers_deleted=${load_balancer_delete_count}"
  echo "target_groups_deleted=${target_group_delete_count}"
  echo 'terraform_apply_executed=false'
  echo 'terraform_destroy_executed=false'
  echo 'service_residual_check=passed'
} >> "$OUTPUT_DIR/execution-summary.txt"

jq -n \
  --argjson load_balancers_deleted "$load_balancer_delete_count" \
  --argjson target_groups_deleted "$target_group_delete_count" \
  --argjson load_balancer_remaining "$load_balancer_remaining" \
  --argjson target_group_remaining "$target_group_remaining" \
  '{
    stage:"kubernetes-owners",
    cleanup_mode:"direct-aws-external-owners",
    load_balancers_deleted:$load_balancers_deleted,
    target_groups_deleted:$target_groups_deleted,
    load_balancer_remaining:$load_balancer_remaining,
    target_group_remaining:$target_group_remaining,
    in_cluster_resources_deferred_to_eks_destroy:true,
    owners_removed:true,
    contract:"idempotent-direct-recovery"
  }' > "$OUTPUT_DIR/kubernetes-owner-recovery.json"
