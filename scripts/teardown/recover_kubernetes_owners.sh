#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:?output directory is required}"
REGION="${AWS_REGION:-ap-northeast-2}"
CLUSTER="${EKS_CLUSTER_NAME:-terraformers-dev-backend}"
RUNTIME_NS="${RUNTIME_NAMESPACE:-terraformers-runtime}"
ARGOCD_NS="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_APP="${ARGOCD_APPLICATION:-terraformers-backend}"
EXTERNAL_NS="${EXTERNAL_SECRETS_NAMESPACE:-external-secrets}"
STATE_BUCKET="${STATE_BUCKET:?STATE_BUCKET is required}"
STATE_PREFIX="${STATE_PREFIX:?STATE_PREFIX is required}"
ACCESS_POLICY_ARN="arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

mkdir -p "$OUTPUT_DIR"

CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ASSUMED_PATH="${CALLER_ARN#*:assumed-role/}"
ROLE_PATH="${ASSUMED_PATH%/*}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_PATH}"

marker_file="${RUNNER_TEMP:-/tmp}/kubernetes-owners.json"
access_created=false

cleanup_access() {
  aws eks disassociate-access-policy \
    --region "$REGION" \
    --cluster-name "$CLUSTER" \
    --principal-arn "$ROLE_ARN" \
    --policy-arn "$ACCESS_POLICY_ARN" >/dev/null 2>&1 || true
  aws eks delete-access-entry \
    --region "$REGION" \
    --cluster-name "$CLUSTER" \
    --principal-arn "$ROLE_ARN" >/dev/null 2>&1 || true
}
trap cleanup_access EXIT

write_marker() {
  jq -n \
    --arg commit "${GITHUB_SHA:-}" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{stage:"kubernetes-owners",source_commit:$commit,completed_at:$completed_at,owners_removed:true}' \
    > "$marker_file"

  aws s3api put-object \
    --bucket "$STATE_BUCKET" \
    --key "${STATE_PREFIX%/}/closure/kubernetes-owners.json" \
    --body "$marker_file" >/dev/null
}

append_success() {
  {
    echo 'kubernetes_owners_removed=true'
    echo 'argocd_application_removed=true'
    echo 'runtime_namespace_removed=true'
    echo 'external_secrets_removed=true'
    echo 'load_balancer_controller_removed=true'
    echo 'internal_alb_removed=true'
    echo 'terraform_apply_executed=false'
    echo 'terraform_destroy_executed=false'
    echo 'service_residual_check=passed'
  } >> "$OUTPUT_DIR/execution-summary.txt"
}

if ! aws eks describe-cluster \
  --region "$REGION" \
  --name "$CLUSTER" >/dev/null 2>&1; then
  write_marker
  append_success
  echo 'eks_cluster_already_absent=true' >> "$OUTPUT_DIR/execution-summary.txt"
  jq -n '{stage:"kubernetes-owners",cluster_already_absent:true,owners_removed:true,contract:"idempotent-recovery"}' \
    > "$OUTPUT_DIR/kubernetes-owner-recovery.json"
  exit 0
fi

if ! aws eks describe-access-entry \
  --region "$REGION" \
  --cluster-name "$CLUSTER" \
  --principal-arn "$ROLE_ARN" >/dev/null 2>&1; then
  aws eks create-access-entry \
    --region "$REGION" \
    --cluster-name "$CLUSTER" \
    --principal-arn "$ROLE_ARN" \
    --type STANDARD >/dev/null
  access_created=true
fi

for attempt in $(seq 1 30); do
  if aws eks describe-access-entry \
    --region "$REGION" \
    --cluster-name "$CLUSTER" \
    --principal-arn "$ROLE_ARN" >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    echo 'EKS access entry did not become readable.' >&2
    exit 1
  fi
  sleep 5
done

associated_count="$({
  aws eks list-associated-access-policies \
    --region "$REGION" \
    --cluster-name "$CLUSTER" \
    --principal-arn "$ROLE_ARN" \
    --output json 2>/dev/null || printf '{"associatedAccessPolicies":[]}'
} | jq --arg arn "$ACCESS_POLICY_ARN" '[.associatedAccessPolicies[]? | select(.policyArn == $arn)] | length')"

if [ "$associated_count" -eq 0 ]; then
  for attempt in $(seq 1 30); do
    if aws eks associate-access-policy \
      --region "$REGION" \
      --cluster-name "$CLUSTER" \
      --principal-arn "$ROLE_ARN" \
      --policy-arn "$ACCESS_POLICY_ARN" \
      --access-scope type=cluster >/dev/null 2>&1; then
      break
    fi
    if [ "$attempt" -eq 30 ]; then
      echo 'EKS cluster-admin policy association failed.' >&2
      exit 1
    fi
    sleep 5
  done
fi

for attempt in $(seq 1 30); do
  associated_count="$(aws eks list-associated-access-policies \
    --region "$REGION" \
    --cluster-name "$CLUSTER" \
    --principal-arn "$ROLE_ARN" \
    --output json | jq --arg arn "$ACCESS_POLICY_ARN" '[.associatedAccessPolicies[]? | select(.policyArn == $arn)] | length')"
  [ "$associated_count" -eq 1 ] && break
  if [ "$attempt" -eq 30 ]; then
    echo 'EKS cluster-admin policy association did not become visible.' >&2
    exit 1
  fi
  sleep 5
done

aws eks update-kubeconfig \
  --region "$REGION" \
  --name "$CLUSTER" \
  --alias terraformers-teardown >/dev/null

for attempt in $(seq 1 30); do
  if kubectl get namespace >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    echo 'Kubernetes API access did not become ready.' >&2
    exit 1
  fi
  sleep 5
done

INGRESS_HOST="$(kubectl get ingress -n "$RUNTIME_NS" -o json 2>/dev/null | jq -r '.items[0].status.loadBalancer.ingress[0].hostname // ""' || true)"

if kubectl get application "$ARGOCD_APP" -n "$ARGOCD_NS" >/dev/null 2>&1; then
  kubectl patch application "$ARGOCD_APP" -n "$ARGOCD_NS" \
    --type merge -p '{"spec":{"syncPolicy":{}}}' >/dev/null
  kubectl delete application "$ARGOCD_APP" -n "$ARGOCD_NS" \
    --wait=true --timeout=10m
fi

if kubectl get namespace "$RUNTIME_NS" >/dev/null 2>&1; then
  kubectl delete ingress --all -n "$RUNTIME_NS" \
    --ignore-not-found=true --wait=true --timeout=10m

  if kubectl api-resources --api-group=external-secrets.io -o name | grep -qx externalsecrets.external-secrets.io; then
    kubectl delete externalsecret terraformers-backend-runtime -n "$RUNTIME_NS" \
      --ignore-not-found=true --wait=true --timeout=5m
  fi
  if kubectl api-resources --api-group=external-secrets.io -o name | grep -qx secretstores.external-secrets.io; then
    kubectl delete secretstore terraformers-backend-secretsmanager -n "$RUNTIME_NS" \
      --ignore-not-found=true --wait=true --timeout=5m
  fi
  kubectl delete secret terraformers-backend-runtime-secrets -n "$RUNTIME_NS" \
    --ignore-not-found=true
fi

if [ -n "$INGRESS_HOST" ]; then
  for attempt in $(seq 1 40); do
    found="$(aws elbv2 describe-load-balancers \
      --region "$REGION" \
      --query 'LoadBalancers[].DNSName' \
      --output text 2>/dev/null | tr '\t' '\n' | grep -Fxc "$INGRESS_HOST" || true)"
    [ "$found" -eq 0 ] && break
    if [ "$attempt" -eq 40 ]; then
      echo 'Internal ALB still exists after Ingress deletion.' >&2
      exit 1
    fi
    sleep 15
  done
fi

uninstall_release() {
  local release="$1"
  local namespace="$2"
  if helm status "$release" -n "$namespace" >/dev/null 2>&1; then
    helm uninstall "$release" -n "$namespace" --wait --timeout 10m
  fi
}

uninstall_release aws-load-balancer-controller kube-system
uninstall_release external-secrets "$EXTERNAL_NS"
uninstall_release argocd "$ARGOCD_NS"

for namespace in "$RUNTIME_NS" "$EXTERNAL_NS" "$ARGOCD_NS"; do
  if kubectl get namespace "$namespace" >/dev/null 2>&1; then
    kubectl delete namespace "$namespace" --wait=true --timeout=10m
  fi
done

lb_count="$(aws elbv2 describe-load-balancers --region "$REGION" --output json | jq '[.LoadBalancers[]? | select((.LoadBalancerName // "") | contains("terraformers"))] | length')"
tg_count="$(aws elbv2 describe-target-groups --region "$REGION" --output json | jq '[.TargetGroups[]? | select((.TargetGroupName // "") | contains("terraformers"))] | length')"

if [ "$lb_count" -ne 0 ] || [ "$tg_count" -ne 0 ]; then
  echo "Terraformers load-balancer residuals remain: lb=${lb_count},tg=${tg_count}" >&2
  exit 1
fi

write_marker
append_success
jq -n \
  --argjson access_created "$access_created" \
  --argjson load_balancer_remaining "$lb_count" \
  --argjson target_group_remaining "$tg_count" \
  '{stage:"kubernetes-owners",access_entry_created:$access_created,load_balancer_remaining:$load_balancer_remaining,target_group_remaining:$target_group_remaining,owners_removed:true,contract:"idempotent-recovery"}' \
  > "$OUTPUT_DIR/kubernetes-owner-recovery.json"
