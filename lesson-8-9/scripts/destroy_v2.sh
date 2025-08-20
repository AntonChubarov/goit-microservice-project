#!/bin/sh
set -eu

# Safe destroy that removes K8s LoadBalancer Services first, waits for AWS ELBs to vanish,
# then destroys Terraform. Also avoids requiring GitHub vars.

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found" >&2; exit 1; }; }
need terraform
need aws
need kubectl
need helm

echo "== Region: ${REGION} =="

# ---- keep GitHub vars optional (so destroy doesn't prompt) ----
export TF_VAR_github_user="${TF_VAR_github_user:-dummy-user}"
export TF_VAR_github_pat="${TF_VAR_github_pat:-dummy-token}"
export TF_VAR_github_repo_url="${TF_VAR_github_repo_url:-https://example.invalid/dummy.git}"
export TF_VAR_region="${TF_VAR_region:-$REGION}"

echo "== Terraform init =="
terraform -chdir="${ROOT_DIR}" init -upgrade

# Try to discover EKS/VPC for cleanup
EKS_CLUSTER_NAME="$(terraform -chdir="${ROOT_DIR}" output -raw eks_cluster_name 2>/dev/null || true)"
if [ -n "${EKS_CLUSTER_NAME}" ]; then
  echo "== Updating kubeconfig for cluster: ${EKS_CLUSTER_NAME} =="
  aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}" >/dev/null 2>&1 || true
  VPC_ID="$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" \
      --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || true)"
else
  VPC_ID=""
  echo "WARN: Could not read 'eks_cluster_name' from Terraform outputs; proceeding without kubeconfig update."
fi

# -------- PRE-DESTROY: remove K8s LoadBalancer Services (Jenkins/Argo and any others) --------
echo "== Removing Kubernetes LoadBalancer services (to delete ELBs/NLBs) =="

# best-effort Helm uninstalls (ignore errors if missing)
helm -n jenkins uninstall jenkins >/dev/null 2>&1 || true
helm -n argocd uninstall argo-cd >/dev/null 2>&1 || true
helm -n argocd uninstall argo_cd >/dev/null 2>&1 || true
helm -n argocd uninstall argocd >/dev/null 2>&1 || true

# delete any remaining Services of type LoadBalancer in ALL namespaces
if kubectl api-resources >/dev/null 2>&1; then
  # enumerate and delete LB Services
  LB_SVCS="$(kubectl get svc -A --no-headers 2>/dev/null | awk '$5=="LoadBalancer"{print $1, $2}' || true)"
  echo "${LB_SVCS}" | while IFS=' ' read -r NS NAME; do
    [ -n "${NS:-}" ] && [ -n "${NAME:-}" ] && kubectl -n "${NS}" delete svc "${NAME}" --ignore-not-found=true || true
  done
fi

# -------- TARGETED DESTROY: remove Helm releases managed by TF, then the rest --------
echo "== Terraform destroy (target: Jenkins & Argo CD) =="
# If these modules don't exist in state, ignore the error
terraform -chdir="${ROOT_DIR}" destroy -auto-approve \
  -target=module.argo_cd \
  -target=module.jenkins || true

# -------- WAIT for all ELBs in the VPC to disappear (prevents subnet/route/IGW block) --------
wait_elbs_gone() {
  VPC="$1"
  [ -z "${VPC}" ] && return 0
  echo "== Waiting for ELBs/NLBs in VPC ${VPC} to be deleted =="

  ATTEMPTS=60   # ~10 minutes (60 * 10s)
  i=1
  while [ "$i" -le "$ATTEMPTS" ]; do
    ELBV2_CNT="$(aws elbv2 describe-load-balancers \
      --query "length(LoadBalancers[?VpcId=='${VPC}'])" --output text 2>/dev/null || echo 0)"
    CLASSIC_CNT="$(aws elb describe-load-balancers \
      --query "length(LoadBalancerDescriptions[?VPCId=='${VPC}'])" --output text 2>/dev/null || echo 0)"

    # Sanitize to numeric (dash/posix-safe)
    case "$ELBV2_CNT" in ''|*[!0-9]*) ELBV2_CNT=0 ;; esac
    case "$CLASSIC_CNT" in ''|*[!0-9]*) CLASSIC_CNT=0 ;; esac

    TOTAL=$(( ELBV2_CNT + CLASSIC_CNT ))
    echo "  Remaining: elbv2=${ELBV2_CNT}, classic=${CLASSIC_CNT}"
    if [ "$TOTAL" -eq 0 ]; then
      echo "  OK: No load balancers remain."
      return 0
    fi
    sleep 10
    i=$((i+1))
  done

  echo "WARN: Some load balancers still exist; continuing with destroy (AWS eventual consistency may still allow deletes)."
  return 0
}

wait_elbs_gone "${VPC_ID}"

# -------- FINAL DESTROY: everything else (VPC/IGW/etc.) --------
echo "== Terraform destroy (everything) =="
terraform -chdir="${ROOT_DIR}" destroy -auto-approve

echo "✅ Destroy complete."
