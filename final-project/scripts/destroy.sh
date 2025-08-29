#!/bin/sh
set -eu

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

# ---- never prompt interactively ----
export TF_INPUT=0

# ---- optional GitHub vars (dummy defaults) ----
export TF_VAR_github_user="${TF_VAR_github_user:-dummy-user}"
export TF_VAR_github_pat="${TF_VAR_github_pat:-dummy-token}"
export TF_VAR_github_repo_url="${TF_VAR_github_repo_url:-https://example.invalid/dummy.git}"
export TF_VAR_region="${TF_VAR_region:-$REGION}"

# ---- ensure all ArgoCD module DB vars are present (dummy, non-empty) ----
# These prevent Terraform from prompting during targeted/full destroy.
export TF_VAR_rds_username="${TF_VAR_rds_username:-postgres}"
export TF_VAR_rds_db_name="${TF_VAR_rds_db_name:-myapp}"
export TF_VAR_rds_password="${TF_VAR_rds_password:-SamplePassw0rd123!}"
# Must look like a hostname (optionally with :port) to satisfy validation.
export TF_VAR_rds_endpoint="${TF_VAR_rds_endpoint:-dummy.example.com}"

echo "== Terraform init =="
terraform -chdir="${ROOT_DIR}" init -upgrade

# Try to discover EKS/VPC
EKS_CLUSTER_NAME="$(terraform -chdir="${ROOT_DIR}" output -raw eks_cluster_name 2>/dev/null || true)"
if [ -n "${EKS_CLUSTER_NAME}" ]; then
  echo "== Updating kubeconfig for cluster: ${EKS_CLUSTER_NAME} =="
  aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}" >/dev/null 2>&1 || true
  VPC_ID="$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" \
      --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || true)"
else
  VPC_ID=""
  echo "WARN: Could not read 'eks_cluster_name' from Terraform outputs."
fi

# -------- remove K8s LoadBalancer Services --------
echo "== Removing Kubernetes LoadBalancer services =="
helm -n jenkins uninstall jenkins >/dev/null 2>&1 || true
helm -n argocd uninstall argo-cd >/dev/null 2>&1 || true
helm -n argocd uninstall argo_cd >/dev/null 2>&1 || true
helm -n argocd uninstall argocd >/dev/null 2>&1 || true

if kubectl api-resources >/dev/null 2>&1; then
  kubectl get svc -A --no-headers 2>/dev/null | awk '$5=="LoadBalancer"{print $1, $2}' \
  | while read -r NS NAME; do
      [ -n "$NS" ] && [ -n "$NAME" ] && kubectl -n "$NS" delete svc "$NAME" --ignore-not-found=true || true
    done
fi

# -------- targeted destroy --------
echo "== Terraform destroy (Jenkins & Argo CD) =="
terraform -chdir="${ROOT_DIR}" destroy -auto-approve \
  -target=module.argo_cd \
  -target=module.jenkins || true

# -------- proactive ELB cleanup --------
echo "== Deleting any remaining Classic ELBs in VPC ${VPC_ID} =="
if [ -n "$VPC_ID" ]; then
  aws elb describe-load-balancers --query "LoadBalancerDescriptions[?VPCId=='${VPC_ID}'].LoadBalancerName" \
    --output text --region "$REGION" 2>/dev/null | tr '\t' '\n' | while read -r ELB; do
      [ -n "$ELB" ] && echo "Deleting classic ELB: $ELB" && \
        aws elb delete-load-balancer --load-balancer-name "$ELB" --region "$REGION" || true
    done
fi

# -------- wait for ELBs to vanish --------
wait_elbs_gone() {
  VPC="$1"
  [ -z "$VPC" ] && return 0
  echo "== Waiting for ELBs/NLBs in VPC $VPC to be deleted =="

  for i in $(seq 1 60); do
    ELBV2_CNT="$(aws elbv2 describe-load-balancers --query "length(LoadBalancers[?VpcId=='${VPC}'])" \
      --output text --region "$REGION" 2>/dev/null || echo 0)"
    CLASSIC_CNT="$(aws elb describe-load-balancers --query "length(LoadBalancerDescriptions[?VPCId=='${VPC}'])" \
      --output text --region "$REGION" 2>/dev/null || echo 0)"

    case "$ELBV2_CNT" in ''|*[!0-9]*) ELBV2_CNT=0 ;; esac
    case "$CLASSIC_CNT" in ''|*[!0-9]*) CLASSIC_CNT=0 ;; esac

    TOTAL=$((ELBV2_CNT + CLASSIC_CNT))
    echo "  Remaining: elbv2=${ELBV2_CNT}, classic=${CLASSIC_CNT}"

    [ "$TOTAL" -eq 0 ] && echo "  OK: No load balancers remain." && return 0
    sleep 10
  done

  echo "WARN: Some load balancers still exist; continuing anyway."
}

wait_elbs_gone "$VPC_ID"

# -------- final destroy --------
echo "== Terraform destroy (everything) =="
terraform -chdir="${ROOT_DIR}" destroy -auto-approve

echo "✅ Destroy complete."
