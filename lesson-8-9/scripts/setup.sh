#!/bin/sh
set -eu

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

terraform init -upgrade
terraform apply -auto-approve

EKS_CLUSTER_NAME="$(terraform output -raw eks_cluster_name)"
aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}"

JENKINS_URL="$(terraform output -raw jenkins_url || true)"
ARGOCD_URL="$(terraform output -raw argocd_url || true)"

[ -n "${JENKINS_URL}" ] && echo "Jenkins UI: ${JENKINS_URL}"
if [ -n "${ARGOCD_URL}" ]; then
  echo "Argo CD UI: ${ARGOCD_URL}"
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true
  echo ""
fi
