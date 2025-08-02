#!/bin/sh
set -eu

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

echo ">> Terraform init/apply ..."
terraform init -upgrade
terraform apply -auto-approve

EKS_CLUSTER_NAME="$(terraform output -raw eks_cluster_name)"
ECR_REPO_URL="$(terraform output -raw ecr_repository_url || true)"

echo ">> Updating kubeconfig for cluster: ${EKS_CLUSTER_NAME} (region: ${REGION})"
aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}"

wait_lb() {
  NS="$1"
  SVC="$2"
  PROTO="$3"
  i=0
  while [ $i -lt 60 ]; do
    HOST="$(kubectl -n "${NS}" get svc "${SVC}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    [ -z "${HOST}" ] && HOST="$(kubectl -n "${NS}" get svc "${SVC}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [ -n "${HOST}" ]; then
      echo "${PROTO}://${HOST}"
      return 0
    fi
    i=$((i+1))
    printf "."
    sleep 10
  done
  echo ""
  return 1
}

echo ">> Waiting for Jenkins LoadBalancer ..."
JENKINS_URL="$(wait_lb jenkins jenkins http || true)"
echo ""
echo ">> Waiting for Argo CD LoadBalancer ..."
ARGOCD_URL="$(wait_lb argocd argo-cd-argocd-server http || true)"
echo ""

if [ -z "${JENKINS_URL}" ]; then
  JENKINS_URL="$(terraform output -raw jenkins_url || true)"
fi
if [ -z "${ARGOCD_URL}" ]; then
  ARGOCD_URL="$(terraform output -raw argocd_url || true)"
fi

echo "====================================="
echo "Deployment complete"
[ -n "${ECR_REPO_URL}" ] && echo "ECR repo: ${ECR_REPO_URL}"
[ -n "${JENKINS_URL}" ] && echo "Jenkins UI: ${JENKINS_URL}"
if [ -n "${ARGOCD_URL}" ]; then
  echo "Argo CD UI: ${ARGOCD_URL}"
  echo "Initial Argo CD admin password:"
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true
  echo ""
fi
echo "====================================="
