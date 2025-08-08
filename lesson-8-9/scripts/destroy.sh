#!/bin/sh
set -eu

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

VPC_ID="$(terraform output -raw vpc_id || true)"
EKS_CLUSTER_NAME="$(terraform output -raw eks_cluster_name || true)"

# Try to auth to the cluster so kubectl deletions work
if [ -n "${EKS_CLUSTER_NAME}" ]; then
  aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}" >/dev/null 2>&1 || true
fi

# 1) Nuke Argo CD objects & CRDs to avoid finalizer stalls
kubectl -n argocd delete applications --all --ignore-not-found=true --timeout=90s || true
kubectl -n argocd delete applicationsets --all --ignore-not-found=true --timeout=90s || true
kubectl -n argocd delete appprojects --all --ignore-not-found=true --timeout=90s || true

for r in applications applicationsets appprojects; do
  kubectl -n argocd get "$r" -o name 2>/dev/null | xargs -r -n1 \
    kubectl -n argocd patch --type merge -p '{"metadata":{"finalizers":[]}}' || true
done

kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io \
  --ignore-not-found=true || true

# 2) Remove all LoadBalancer Services to trigger ELB deletion
kubectl get svc -A 2>/dev/null | awk '$5=="LoadBalancer"{print $1,$2}' \
  | xargs -r -n2 sh -c 'kubectl -n "$0" delete svc "$1"' || true

# 3) Tear down k8s/helm stacks that create LBs & ENIs
terraform destroy -target=module.argo_cd -target=module.jenkins -auto-approve || true
terraform destroy -target=module.eks -auto-approve || true

# 4) Wait for ELBv2 to disappear from the VPC (prevents VPC/IGW deps)
if [ -n "${VPC_ID}" ]; then
  i=0
  while [ $i -lt 60 ]; do
    cnt="$(aws elbv2 describe-load-balancers \
      --query "length(LoadBalancers[?VpcId=='${VPC_ID}'])" --output text 2>/dev/null || echo 0)"
    [ "${cnt}" = "0" ] && break
    sleep 10
    i=$((i+1))
  done
fi

# 5) Proactively remove public route table & IGW before the rest of VPC (fast)
#    This prevents 'aws_internet_gateway.this: Still destroying...' caused by
#    slow NAT GW teardown.
terraform destroy -target=module.vpc.aws_route_table_association.public -auto-approve || true
terraform destroy -target=module.vpc.aws_route_table.public -auto-approve || true
terraform destroy -target=module.vpc.aws_internet_gateway.this -auto-approve || true

# 6) Now destroy the remainder of the VPC (subnets, NAT GW, EIPs, etc.)
terraform destroy -target=module.vpc -auto-approve || true

# 7) Final sweep (anything left)
terraform destroy -auto-approve || true
