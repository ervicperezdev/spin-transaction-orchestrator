#!/usr/bin/env bash
set -Eeuo pipefail

: "${DEPLOY_HOSTNAME:?DEPLOY_HOSTNAME must be the Terraform environment hostname}"
namespace="${KUBERNETES_NAMESPACE:-transaction-api}"
release="${HELM_RELEASE:-transaction-api}"
timeout_seconds="${POST_DEPLOY_TIMEOUT_SECONDS:-300}"

diagnose() {
  local result=$?
  if (( result != 0 )); then
    echo 'Post-deploy smoke failed; diagnostics follow.' >&2
    kubectl -n "$namespace" get deployment,pods,svc,endpointslice -l "app.kubernetes.io/instance=$release" -o wide || true
    kubectl -n "$namespace" describe ingress "$release" || true
    kubectl -n "$namespace" get events --sort-by=.lastTimestamp | tail -n 80 || true
  fi
  exit "$result"
}
trap diagnose EXIT

echo 'Checking Kubernetes rollout and ready targets...'
kubectl -n "$namespace" rollout status "deployment/$release" --timeout="${timeout_seconds}s"
kubectl -n "$namespace" get endpointslice -l "kubernetes.io/service-name=$release" -o yaml

echo 'Checking Ingress and ALB provisioning...'
kubectl -n "$namespace" get ingress "$release" -o yaml
deadline=$((SECONDS + timeout_seconds))
while :; do
  alb_hostname="$(kubectl -n "$namespace" get ingress "$release" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
  if [[ -n "$alb_hostname" ]]; then break; fi
  if (( SECONDS >= deadline )); then
    echo 'Ingress has no ALB hostname before timeout.' >&2
    exit 1
  fi
  sleep 10
done
echo "ALB hostname: $alb_hostname"

certificate_arn="$(kubectl -n "$namespace" get ingress "$release" -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/certificate-arn}')"
if [[ -z "$certificate_arn" ]]; then
  echo 'Ingress is missing its ACM certificate annotation.' >&2
  exit 1
fi
echo 'Checking ACM certificate status...'
aws acm describe-certificate --certificate-arn "$certificate_arn" \
  --query 'Certificate.{Status:Status,DomainName:DomainName,NotAfter:NotAfter}' --output table
certificate_status="$(aws acm describe-certificate --certificate-arn "$certificate_arn" --query 'Certificate.Status' --output text)"
[[ "$certificate_status" == 'ISSUED' ]] || { echo "ACM certificate status is $certificate_status, expected ISSUED." >&2; exit 1; }

echo 'Checking DNS resolution against the provisioned ALB...'
dns_addresses="$(getent ahostsv4 "$DEPLOY_HOSTNAME" | awk '{print $1}' | sort -u)"
[[ -n "$dns_addresses" ]] || { echo "DNS does not resolve $DEPLOY_HOSTNAME." >&2; exit 1; }
echo "$dns_addresses"

echo 'Checking public HTTPS path (Route 53 -> WAF -> ALB/ACM -> EKS)...'
curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
  "https://${DEPLOY_HOSTNAME}/actuator/health" >/dev/null
