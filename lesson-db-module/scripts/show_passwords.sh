#!/bin/sh
set -eu

# Show Argo CD and Jenkins admin credentials from the EKS cluster.
# Uses default AWS profile and region us-east-1 unless overridden via env.
#
# Usage:
#   ./scripts/show_passwords.sh
#
# Notes:
# - Assumes Terraform has already created EKS and Argo CD / Jenkins via Helm.
# - If the Argo CD initial admin secret was deleted, we try a Terraform output fallback.

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found in PATH" >&2; exit 1; }; }
need aws
need kubectl
need terraform
need base64
need sed

b64d() {
  # Portable-ish base64 decode (Linux/macOS)
  base64 -d 2>/dev/null || base64 -D 2>/dev/null
}

echo "== Region: ${REGION} =="

# Try to discover cluster name from Terraform outputs (optional but helpful)
EKS_CLUSTER_NAME="$(terraform -chdir="${ROOT_DIR}" output -raw eks_cluster_name 2>/dev/null || true)"

if [ -n "${EKS_CLUSTER_NAME}" ]; then
  echo "== Updating kubeconfig for cluster: ${EKS_CLUSTER_NAME} =="
  aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}" >/dev/null
else
  echo "WARN: Could not read 'eks_cluster_name' from Terraform outputs; assuming kubeconfig is already pointed at the right cluster."
fi

echo
echo "==================== Argo CD ===================="
ARGO_NS="argocd"
ARGO_SECRET="argocd-initial-admin-secret"
ARGO_USER="admin"

ARGO_PW=""
if kubectl -n "${ARGO_NS}" get secret "${ARGO_SECRET}" >/dev/null 2>&1; then
  ARGO_PW="$(kubectl -n "${ARGO_NS}" get secret "${ARGO_SECRET}" -o jsonpath='{.data.password}' | b64d || true)"
fi

if [ -z "${ARGO_PW}" ]; then
  # Fallback: try Terraform output if your infra module exposes it
  ARGO_PW="$(terraform -chdir="${ROOT_DIR}" output -raw argocd_admin_password 2>/dev/null || true)"
fi

if [ -n "${ARGO_PW}" ]; then
  echo "Username: ${ARGO_USER}"
  echo "Password: ${ARGO_PW}"
else
  echo "Password: (unavailable)"
  echo "Hint: If the initial secret was deleted, reset the admin password via Argo CD docs (or expose it via Terraform output)."
fi

echo
echo "==================== Jenkins ===================="
JENKINS_NS="jenkins"
JENKINS_SECRET="jenkins"  # Helm chart usually creates this with admin creds
JENKINS_USER="$(kubectl -n "${JENKINS_NS}" get secret "${JENKINS_SECRET}" -o jsonpath='{.data.jenkins-admin-user}' 2>/dev/null | b64d || true)"
JENKINS_PW="$(kubectl -n "${JENKINS_NS}" get secret "${JENKINS_SECRET}" -o jsonpath='{.data.jenkins-admin-password}' 2>/dev/null | b64d || true)"

# As a convenience, if values.yaml hard-coded admin credentials, you might already know them.
# We still prefer reading from the Secret so this stays in sync with the chart.

if [ -n "${JENKINS_USER}" ] || [ -n "${JENKINS_PW}" ]; then
  [ -n "${JENKINS_USER}" ] && echo "Username: ${JENKINS_USER}" || echo "Username: (unavailable)"
  [ -n "${JENKINS_PW}" ]   && echo "Password: ${JENKINS_PW}"   || echo "Password: (unavailable)"
else
  echo "Credentials: (unavailable)"
  echo "Hint: Ensure the Jenkins Helm release created the admin Secret '${JENKINS_SECRET}' in namespace '${JENKINS_NS}'."
fi

echo
echo "Done."
