#!/bin/sh
set -eu

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

VPC_ID="$(terraform output -raw vpc_id || true)"
EKS_CLUSTER_NAME="$(terraform output -raw eks_cluster_name || true)"

if [ -n "${EKS_CLUSTER_NAME}" ]; then
  aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}" >/dev/null 2>&1 || true
fi

kubectl -n argocd delete applications --all --ignore-not-found=true --timeout=90s || true
kubectl -n argocd delete applicationsets --all --ignore-not-found=true --timeout=90s || true
kubectl -n argocd delete appprojects --all --ignore-not-found=true --timeout=90s || true

for r in applications applicationsets appprojects; do
  kubectl -n argocd get "$r" -o name 2>/dev/null | xargs -r -n1 kubectl -n argocd patch --type merge -p '{"metadata":{"finalizers":[]}}' || true
done

kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io --ignore-not-found=true || true

kubectl get svc -A 2>/dev/null | awk '$5=="LoadBalancer"{print $1,$2}' | xargs -r -n2 sh -c 'kubectl -n "$0" delete svc "$1"' || true

terraform destroy -target=module.argo_cd -target=module.jenkins -auto-approve || true
terraform destroy -target=module.eks -auto-approve || true

if [ -n "${VPC_ID}" ]; then
  i=0
  while [ $i -lt 60 ]; do
    cnt="$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId=='${VPC_ID}'])" --output text 2>/dev/null || echo 0)"
    [ "${cnt}" = "0" ] && break
    sleep 10
    i=$((i+1))
  done
fi

terraform destroy -target=module.vpc -auto-approve || true
terraform destroy -auto-approve || true
