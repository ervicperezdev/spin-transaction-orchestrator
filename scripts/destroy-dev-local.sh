#!/usr/bin/env bash
# Generate a reviewed dev destroy plan locally and, only with --apply plus an
# interactive confirmation, apply that exact binary plan.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: BACKEND_CONFIG=/secure/path/backend.hcl TF_VAR_FILE=/secure/path/dev.tfvars \
  ./scripts/destroy-dev-local.sh [--apply] [--skip-final-snapshot] [--delete-ecr-images]

Without --apply, this command performs the read-only preflight and leaves
terraform/environments/dev/destroy.dev.tfplan for human review. --apply still
requires typing the confirmation phrase and applies that exact local plan.
EOF
}

apply=false
skip_final_snapshot=false
delete_ecr_images=false
while (($#)); do
  case "$1" in
    --apply) apply=true ;;
    --skip-final-snapshot) skip_final_snapshot=true ;;
    --delete-ecr-images) delete_ecr_images=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

: "${BACKEND_CONFIG:?Set BACKEND_CONFIG to your private backend.hcl path}"
: "${TF_VAR_FILE:?Set TF_VAR_FILE to your private dev tfvars path}"
[[ -r "$BACKEND_CONFIG" ]] || { echo "Cannot read BACKEND_CONFIG: $BACKEND_CONFIG" >&2; exit 2; }
[[ -r "$TF_VAR_FILE" ]] || { echo "Cannot read TF_VAR_FILE: $TF_VAR_FILE" >&2; exit 2; }

for command in terraform aws kubectl helm jq; do
  command -v "$command" >/dev/null || { echo "Required command is missing: $command" >&2; exit 2; }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment_dir="$repo_root/terraform/environments/dev"
plan_path="$environment_dir/destroy.dev.tfplan"
runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/spin-dev-teardown.XXXXXX")"
teardown_vars="$runtime_dir/teardown.auto.tfvars"
trap 'rm -rf "$runtime_dir"' EXIT
export RUNNER_TEMP="$runtime_dir"

export AWS_REGION="${AWS_REGION:-us-east-1}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-spin-transaction-orchestrator-cluster}"
export ECR_REPOSITORY_NAME="${ECR_REPOSITORY_NAME:-spin-transaction-orchestrator}"
export RDS_IDENTIFIER="${RDS_IDENTIFIER:-spin-transaction-orchestrator-dev}"
export RDS_SKIP_FINAL_SNAPSHOT="$skip_final_snapshot"
export ECR_FORCE_DELETE="$delete_ecr_images"
export RDS_FINAL_SNAPSHOT_IDENTIFIER="${RDS_FINAL_SNAPSHOT_IDENTIFIER:-${RDS_IDENTIFIER}-final-$(date -u +%Y%m%d%H%M%S)}"

umask 077
cat > "$teardown_vars" <<EOF
rds_skip_final_snapshot       = $RDS_SKIP_FINAL_SNAPSHOT
rds_final_snapshot_identifier = "$RDS_FINAL_SNAPSHOT_IDENTIFIER"
ecr_force_delete              = $ECR_FORCE_DELETE
EOF

cd "$environment_dir"
terraform init -input=false -backend-config="$BACKEND_CONFIG"
"$repo_root/scripts/terraform-dev-teardown-preflight.sh"

terraform plan -destroy -input=false -no-color \
  -out="$plan_path" \
  -var-file="$TF_VAR_FILE" \
  -var-file="$teardown_vars"

terraform show -json "$plan_path" > "$runtime_dir/destroy-plan.json"
delete_count="$(jq '[.resource_changes[]? | select(.change.actions == ["delete"])] | length' "$runtime_dir/destroy-plan.json")"
replace_count="$(jq '[.resource_changes[]? | select((.change.actions | index("delete")) and (.change.actions | index("create")))] | length' "$runtime_dir/destroy-plan.json")"
echo "Destroy plan saved to: $plan_path"
echo "Actions: delete=$delete_count replace=$replace_count"

if [ "$apply" != true ]; then
  echo "Plan-only complete. Review the plan and rerun with --apply only after explicit human approval."
  exit 0
fi

read -r -p "Type DESTROY-DEV to apply this exact plan: " confirmation
if [ "$confirmation" != "DESTROY-DEV" ]; then
  echo "Destroy not approved; the reviewed plan remains at $plan_path."
  exit 1
fi

terraform apply -input=false "$plan_path"
rm -f "$plan_path"
echo "Destroy apply completed; the local binary plan was removed."
