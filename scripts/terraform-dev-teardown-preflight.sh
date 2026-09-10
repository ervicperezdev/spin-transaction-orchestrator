#!/usr/bin/env bash
# Read-only guard for the dev destroy workflow. It deliberately never runs a
# Helm, kubectl, Terraform or AWS mutation command.
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${EKS_CLUSTER_NAME:?EKS_CLUSTER_NAME is required}"
: "${ECR_REPOSITORY_NAME:?ECR_REPOSITORY_NAME is required}"
: "${RDS_IDENTIFIER:?RDS_IDENTIFIER is required}"
: "${RDS_SKIP_FINAL_SNAPSHOT:?RDS_SKIP_FINAL_SNAPSHOT is required}"
: "${ECR_FORCE_DELETE:?ECR_FORCE_DELETE is required}"

final_snapshot_identifier="${RDS_FINAL_SNAPSHOT_IDENTIFIER:-${RDS_IDENTIFIER}-final}"
blockers=0
vpc_id="$(terraform output -raw vpc_id)"
runtime_tmp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

block() {
  echo "::error::$*" >&2
  blockers=1
}

notice() {
  echo "::notice::$*"
}

echo "## Dev teardown preflight"
echo "This preflight is read-only and does not uninstall Helm releases or delete AWS resources."

aws eks describe-cluster --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME" --query 'cluster.status' --output text >/dev/null
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME" --kubeconfig "$runtime_tmp/teardown-kubeconfig" >/dev/null
export KUBECONFIG="$runtime_tmp/teardown-kubeconfig"

echo "### Helm and Ingress"
helm list --all-namespaces
ingresses="$(kubectl get ingress --all-namespaces -o json)"
ingress_count="$(jq '.items | length' <<<"$ingresses")"
if [ "$ingress_count" -gt 0 ]; then
  block "$ingress_count Ingress resource(s) still exist. Uninstall the transaction-api Helm release and its provider mock, then wait for their Load Balancers to disappear before destroy."
fi

echo "### ALB, target groups and ENIs"
albs="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --output json)"
alb_count="$(jq --arg vpc "$vpc_id" '[.LoadBalancers[] | select(.VpcId == $vpc)] | length' <<<"$albs")"
if [ "$alb_count" -gt 0 ]; then
  block "Found $alb_count ALB/NLB resource(s) in the account/region. Review their VPC and Kubernetes ownership; teardown must not continue while application-created load balancers remain."
fi
target_group_count="$(aws elbv2 describe-target-groups --region "$AWS_REGION" --output json | jq --arg vpc "$vpc_id" '[.TargetGroups[] | select(.VpcId == $vpc)] | length')"
if [ "$target_group_count" -gt 0 ]; then
  block "Found $target_group_count target group(s). Verify no transaction-api Ingress-owned target group remains before destroying the VPC."
fi
eni_count="$(aws ec2 describe-network-interfaces --region "$AWS_REGION" --filters "Name=vpc-id,Values=$vpc_id" "Name=description,Values=ELB*" --output json | jq '.NetworkInterfaces | length')"
if [ "$eni_count" -gt 0 ]; then
  block "Found $eni_count ELB network interface(s). Wait until the load balancer cleanup releases them."
fi

echo "### RDS final snapshot"
if [ "$RDS_SKIP_FINAL_SNAPSHOT" = "true" ]; then
  notice "RDS final snapshot is explicitly disabled for this approved ephemeral cleanup."
else
  if aws rds describe-db-snapshots --region "$AWS_REGION" --db-snapshot-identifier "$final_snapshot_identifier" >/dev/null 2>&1; then
    block "Final snapshot '$final_snapshot_identifier' already exists. Choose a new rds_final_snapshot_identifier or explicitly approve skipping the final snapshot."
  else
    notice "Final snapshot '$final_snapshot_identifier' is available."
  fi
fi

echo "### ECR"
image_count="$(aws ecr describe-images --region "$AWS_REGION" --repository-name "$ECR_REPOSITORY_NAME" --output json 2>/dev/null | jq '.imageDetails | length' || true)"
if [ -n "$image_count" ] && [ "$image_count" -gt 0 ] && [ "$ECR_FORCE_DELETE" != "true" ]; then
  block "ECR repository '$ECR_REPOSITORY_NAME' contains $image_count image(s) and ecr_force_delete=false. Retain the repository or explicitly approve image deletion."
fi

echo "### External foundations"
state_addresses="$(terraform state list)"
if grep -Eq '(^|\.)aws_route53_zone\.' <<<"$state_addresses"; then
  block "A Route 53 hosted zone is present in this state; it must remain externally managed."
fi
if grep -Eq 'aws_iam_openid_connect_provider\.(eks|this)' <<<"$state_addresses"; then
  block "An EKS OIDC provider appears in this state; it must remain externally managed."
fi
notice "Hosted zone and the external EKS OIDC provider are inputs/data, not destroy targets in this environment."

if [ "$blockers" -ne 0 ]; then
  echo "Preflight found teardown blockers. Resolve them and rerun this plan-only workflow." >&2
  exit 1
fi

echo "Preflight passed: generate the destroy plan, review its action counts and artifact, then obtain a separate human approval before any destroy apply."
