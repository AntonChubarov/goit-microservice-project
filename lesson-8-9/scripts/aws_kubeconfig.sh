#!/bin/sh
set -eu

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PROFILE="${AWS_PROFILE:-default}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TF_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${TF_DIR}"

# Get the EKS cluster name from Terraform outputs
EKS_CLUSTER_NAME="$(terraform -chdir="${TF_DIR}" output -raw eks_cluster_name)"

# Update kubeconfig using AWS CLI, with correct profile and region
aws eks update-kubeconfig \
  --name "${EKS_CLUSTER_NAME}" \
  --region "${REGION}" \
  --profile "${PROFILE}"

echo "✅ Kubeconfig updated for cluster '${EKS_CLUSTER_NAME}' in region '${REGION}' (profile: '${PROFILE}')."
echo "   You can now use kubectl or k9s to inspect resources."
