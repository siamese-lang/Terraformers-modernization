#!/usr/bin/env bash

set -euo pipefail

EXPECTED_ACCOUNT_ID="${EXPECTED_ACCOUNT_ID:?EXPECTED_ACCOUNT_ID is required}"
STATE_BUCKET="${STATE_BUCKET:?STATE_BUCKET is required}"
STATE_PREFIX="${STATE_PREFIX:?STATE_PREFIX is required}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-siamese-lang/Terraformers-modernization}"
GITHUB_ENVIRONMENT="${GITHUB_ENVIRONMENT:-aws-live-teardown}"
ROLE_NAME="${ROLE_NAME:-terraformers-live-teardown}"
POLICY_NAME="${POLICY_NAME:-terraformers-runtime-teardown}"
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-terraformers-dev-backend}"

ACTUAL_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
test "${ACTUAL_ACCOUNT_ID}" = "${EXPECTED_ACCOUNT_ID}"

OIDC_PROVIDER_ARN="arn:aws:iam::${EXPECTED_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

OIDC_PROVIDER_COUNT="$(
  aws iam list-open-id-connect-providers \
    --output json |
  tr -d '\r' |
  jq \
    --arg arn "${OIDC_PROVIDER_ARN}" \
    '[.OpenIDConnectProviderList[]? | select(.Arn == $arn)] | length'
)"
test "${OIDC_PROVIDER_COUNT}" -eq 1

EKS_OIDC_PROVIDER_ARN="$(
  issuer="$(
    aws eks describe-cluster \
      --region "${AWS_REGION}" \
      --name "${EKS_CLUSTER_NAME}" \
      --query 'cluster.identity.oidc.issuer' \
      --output text 2>/dev/null |
    tr -d '\r' ||
    true
  )"
  if [ -n "${issuer}" ] && [ "${issuer}" != "None" ]; then
    printf 'arn:aws:iam::%s:oidc-provider/%s\n' \
      "${EXPECTED_ACCOUNT_ID}" \
      "${issuer#https://}"
  fi
)"
test -n "${EKS_OIDC_PROVIDER_ARN}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

cat > "${WORK_DIR}/trust.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Federated": "${OIDC_PROVIDER_ARN}"},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPOSITORY}:environment:${GITHUB_ENVIRONMENT}"
        }
      }
    }
  ]
}
EOF

jq empty "${WORK_DIR}/trust.json"

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  aws iam update-assume-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-document "file://${WORK_DIR}/trust.json"
else
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "file://${WORK_DIR}/trust.json" \
    --max-session-duration 3600 \
    --tags \
      Key=Project,Value=terraformers \
      Key=Environment,Value=dev \
      Key=Component,Value=portfolio-closure \
      Key=ManagedBy,Value=cloudshell-bootstrap >/dev/null
fi

aws iam attach-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess

cat > "${WORK_DIR}/teardown-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformRemoteStateMutation",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::${STATE_BUCKET}",
        "arn:aws:s3:::${STATE_BUCKET}/${STATE_PREFIX%/}/*"
      ]
    },
    {
      "Sid": "ExactProjectBuckets",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::terraformers-dev-rag-corpus-${EXPECTED_ACCOUNT_ID}",
        "arn:aws:s3:::terraformers-dev-rag-corpus-${EXPECTED_ACCOUNT_ID}/*",
        "arn:aws:s3:::terraformers-dev-result-${EXPECTED_ACCOUNT_ID}",
        "arn:aws:s3:::terraformers-dev-result-${EXPECTED_ACCOUNT_ID}/*",
        "arn:aws:s3:::terraformers-dev-upload-${EXPECTED_ACCOUNT_ID}",
        "arn:aws:s3:::terraformers-dev-upload-${EXPECTED_ACCOUNT_ID}/*",
        "arn:aws:s3:::terraformers-modernization-dev-frontend-${EXPECTED_ACCOUNT_ID}",
        "arn:aws:s3:::terraformers-modernization-dev-frontend-${EXPECTED_ACCOUNT_ID}/*"
      ]
    },
    {
      "Sid": "ProjectCloudFrontDeletion",
      "Effect": "Allow",
      "Action": [
        "cloudfront:UpdateDistribution",
        "cloudfront:DeleteDistribution",
        "cloudfront:DeleteFunction",
        "cloudfront:DeleteOriginAccessControl",
        "cloudfront:DeleteVpcOrigin"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ProjectEcrDeletion",
      "Effect": "Allow",
      "Action": "ecr:*",
      "Resource": "arn:aws:ecr:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:repository/terraformers-*"
    },
    {
      "Sid": "ProjectQueueDeletion",
      "Effect": "Allow",
      "Action": ["sqs:DeleteQueue", "sqs:PurgeQueue"],
      "Resource": "arn:aws:sqs:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:terraformers-*"
    },
    {
      "Sid": "ProjectSecretDeletion",
      "Effect": "Allow",
      "Action": ["secretsmanager:DeleteSecret", "secretsmanager:CancelRotateSecret"],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:secret:terraformers*"
    },
    {
      "Sid": "ProjectRdsDeletion",
      "Effect": "Allow",
      "Action": [
        "rds:ModifyDBInstance",
        "rds:DeleteDBInstance",
        "rds:DeleteDBSubnetGroup",
        "rds:DeleteDBSnapshot",
        "rds:DeleteDBInstanceAutomatedBackup",
        "rds:RemoveTagsFromResource"
      ],
      "Resource": "arn:aws:rds:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:*:*terraformers*"
    },
    {
      "Sid": "ProjectCognitoDeletion",
      "Effect": "Allow",
      "Action": ["cognito-idp:DeleteUserPool", "cognito-idp:DeleteUserPoolClient"],
      "Resource": "arn:aws:cognito-idp:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:userpool/*"
    },
    {
      "Sid": "ProjectAossDeletion",
      "Effect": "Allow",
      "Action": [
        "aoss:DeleteCollection",
        "aoss:DeleteAccessPolicy",
        "aoss:DeleteSecurityPolicy",
        "aoss:DeleteVpcEndpoint",
        "aoss:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ProjectCodeBuildDeletion",
      "Effect": "Allow",
      "Action": "codebuild:DeleteProject",
      "Resource": "arn:aws:codebuild:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:project/terraformers-*"
    },
    {
      "Sid": "ProjectEksDeletion",
      "Effect": "Allow",
      "Action": [
        "eks:DeleteAddon",
        "eks:DeleteNodegroup",
        "eks:DeleteCluster",
        "eks:UntagResource"
      ],
      "Resource": [
        "arn:aws:eks:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:cluster/terraformers-*",
        "arn:aws:eks:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:nodegroup/terraformers-*/*/*",
        "arn:aws:eks:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:addon/terraformers-*/*/*"
      ]
    },
    {
      "Sid": "TemporaryEksAccessEntryManagement",
      "Effect": "Allow",
      "Action": [
        "eks:CreateAccessEntry",
        "eks:DeleteAccessEntry",
        "eks:AssociateAccessPolicy",
        "eks:DisassociateAccessPolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ProjectEc2Deletion",
      "Effect": "Allow",
      "Action": [
        "ec2:DeleteVpc",
        "ec2:DeleteSubnet",
        "ec2:DeleteRouteTable",
        "ec2:DeleteRoute",
        "ec2:DisassociateRouteTable",
        "ec2:DeleteNatGateway",
        "ec2:ReleaseAddress",
        "ec2:DisassociateAddress",
        "ec2:DetachInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:DeleteVpcEndpoints",
        "ec2:ModifyVpcEndpoint",
        "ec2:DeleteSecurityGroup",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:DeleteNetworkInterface",
        "ec2:DeleteTags"
      ],
      "Resource": "*",
      "Condition": {"StringEquals": {"aws:RequestedRegion": "${AWS_REGION}"}}
    },
    {
      "Sid": "ProjectLoadBalancerDeletion",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DeleteRule",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:ModifyLoadBalancerAttributes"
      ],
      "Resource": "arn:aws:elasticloadbalancing:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:*/*"
    },
    {
      "Sid": "ProjectIamDeletion",
      "Effect": "Allow",
      "Action": [
        "iam:DetachRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:DeleteRole",
        "iam:DeletePolicy",
        "iam:DeletePolicyVersion",
        "iam:RemoveRoleFromInstanceProfile"
      ],
      "Resource": [
        "arn:aws:iam::${EXPECTED_ACCOUNT_ID}:role/terraformers-*",
        "arn:aws:iam::${EXPECTED_ACCOUNT_ID}:policy/terraformers-*"
      ]
    },
    {
      "Sid": "ExactEksOidcProviderDeletion",
      "Effect": "Allow",
      "Action": [
        "iam:DeleteOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider"
      ],
      "Resource": "${EKS_OIDC_PROVIDER_ARN}"
    },
    {
      "Sid": "ProjectCloudWatchDeletion",
      "Effect": "Allow",
      "Action": ["cloudwatch:DeleteDashboards", "cloudwatch:DeleteAlarms"],
      "Resource": "*"
    },
    {
      "Sid": "ProjectLogDeletion",
      "Effect": "Allow",
      "Action": "logs:DeleteLogGroup",
      "Resource": "arn:aws:logs:${AWS_REGION}:${EXPECTED_ACCOUNT_ID}:log-group:*terraformers*"
    },
    {
      "Sid": "AossManagedPrivateDnsDeletion",
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:DeleteHostedZone",
        "route53:DisassociateVPCFromHostedZone"
      ],
      "Resource": "arn:aws:route53:::hostedzone/*"
    }
  ]
}
EOF

jq empty "${WORK_DIR}/teardown-policy.json"
POLICY_BYTES="$(wc -c < "${WORK_DIR}/teardown-policy.json" | tr -d ' ')"
test "${POLICY_BYTES}" -le 10240

aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "${POLICY_NAME}" \
  --policy-document "file://${WORK_DIR}/teardown-policy.json"

ROLE_ARN="arn:aws:iam::${EXPECTED_ACCOUNT_ID}:role/${ROLE_NAME}"

echo "runtime_teardown_role_bootstrap=completed"
echo "role_arn=${ROLE_ARN}"
echo "github_environment=${GITHUB_ENVIRONMENT}"
echo "trust_subject=repo:${GITHUB_REPOSITORY}:environment:${GITHUB_ENVIRONMENT}"
echo "state_bucket=${STATE_BUCKET}"
echo "state_prefix=${STATE_PREFIX}"
echo "eks_oidc_provider_arn=${EKS_OIDC_PROVIDER_ARN}"
echo "administrator_access_attached=false"
echo "read_only_managed_policy_attached=true"
echo "project_destructive_inline_policy=${POLICY_NAME}"
echo "inline_policy_bytes=${POLICY_BYTES}"
