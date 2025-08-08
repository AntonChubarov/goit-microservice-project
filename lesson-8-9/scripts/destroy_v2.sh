#!/bin/sh
# Safe-mode shell script: delete Helm releases → EKS → everything else.
set -eu

###############################################################################
# Paths & constants
###############################################################################
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

###############################################################################
# Helper: refresh kubeconfig so kubectl/helm have valid credentials
###############################################################################
refresh_kubeconfig() {
  CLUSTER_NAME="$(terraform output -raw eks_cluster_name 2>/dev/null || true)"
  [ -n "$CLUSTER_NAME" ] || return        # cluster might already be gone

  # If you used a dedicated cluster-admin role in your EKS module, output it
  # and pass with --role-arn.  Fallback: let AWS CLI pick current identity.
  if CLUSTER_ADMIN_ROLE="$(terraform output -raw eks_cluster_admin_role_arn 2>/dev/null || true)"; then
    aws eks update-kubeconfig \
      --name "$CLUSTER_NAME" \
      --region "$REGION" \
      --role-arn "$CLUSTER_ADMIN_ROLE" \
      --alias "$CLUSTER_NAME"
  else
    aws eks update-kubeconfig \
      --name "$CLUSTER_NAME" \
      --region "$REGION" \
      --alias "$CLUSTER_NAME"
  fi
}

###############################################################################
# 1. Helm releases (best effort)
###############################################################################
set +e  # ignore errors temporarily

# First try; if we get "Unauthorized", refresh kubeconfig once and retry
helm uninstall django-app
if [ $? -ne 0 ]; then
  echo "Helm uninstall failed — refreshing kubeconfig and retrying once..."
  refresh_kubeconfig
  helm uninstall django-app || true
fi

helm uninstall metrics-server -n kube-system || true

###############################################################################
# 2. Destroy Kubernetes-dependent Terraform modules (jenkins / argo_cd)
###############################################################################
terraform destroy \
  -target=module.jenkins \
  -target=module.argo_cd \
  -auto-approve || true   # ignore failures; cluster may already be broken

###############################################################################
# 3. Destroy the EKS cluster (control plane + node groups)
###############################################################################
terraform destroy \
  -target=module.eks \
  -auto-approve

###############################################################################
# 4. Destroy the rest (VPC, NAT/IGW, etc.) — skip remote state refresh
###############################################################################
terraform destroy \
  -refresh=false \
  -auto-approve

set -e
