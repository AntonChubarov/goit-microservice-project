#!/bin/sh
set -eu

# --- Resolve paths relative to this script ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"   # points to lesson-8-9
JENKINS_NS="${JENKINS_NS:-jenkins}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Wait controls for LoadBalancer provisioning (tunable via env)
LB_WAIT_SECS="${LB_WAIT_SECS:-360}"   # total seconds to wait (default 6 minutes)
LB_POLL_SECS="${LB_POLL_SECS:-10}"    # poll interval seconds

# --- Prompt for GitHub creds (or take from env) ---
if [ -z "${GITHUB_USERNAME:-}" ]; then
  printf "GitHub username: "
  IFS= read -r GITHUB_USERNAME
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  printf "GitHub token (input hidden): "
  stty -echo
  IFS= read -r GITHUB_TOKEN
  stty echo
  printf "\n"
fi

# --- Terraform apply in lesson-8-9 dir ---
terraform -chdir="$TF_DIR" init -upgrade
terraform -chdir="$TF_DIR" apply -auto-approve

# --- Read outputs ---
if CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw eks_cluster_name 2>/dev/null)"; then
  :
else
  echo "ERROR: cannot read 'eks_cluster_name' Terraform output." >&2
  exit 1
fi

# --- Kubeconfig for the new cluster ---
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null

# --- Wait for Jenkins namespace to appear (created by Terraform/Helm) ---
i=0
until kubectl get ns "$JENKINS_NS" >/dev/null 2>&1; do
  i=$((i+1))
  if [ "$i" -gt 24 ]; then
    echo "ERROR: Jenkins namespace '$JENKINS_NS' not found after waiting." >&2
    exit 1
  fi
  sleep 5
done

# --- Create/Update Jenkins credential via Kubernetes Secret (no repo secrets) ---
# Requires the Kubernetes Credentials Provider plugin on Jenkins.
# ID will be 'github-token' (matches Jenkinsfile).
cat <<EOF | kubectl -n "$JENKINS_NS" apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-github-token
  labels:
    jenkins.io/credentials-type: "usernamePassword"
  annotations:
    jenkins.io/credentials-description: "GitHub PAT for pushes"
    jenkins.io/credentials-id: "github-token"
type: kubernetes.io/basic-auth
stringData:
  username: "$GITHUB_USERNAME"
  password: "$GITHUB_TOKEN"
EOF

# Give Jenkins a moment to ingest credentials on first boot
sleep 15

###############################################################################
# Helper: get LB address (hostname or IP) for a service
###############################################################################
get_svc_addr() {
  ns="$1"
  name="$2"
  # Try hostname first
  addr="$(kubectl -n "$ns" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -z "${addr}" ]; then
    # Fallback to IP
    addr="$(kubectl -n "$ns" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  fi
  printf "%s" "${addr}"
}

###############################################################################
# Wait for Argo CD & Jenkins LoadBalancer addresses
###############################################################################
echo "⏳ Waiting for LoadBalancer addresses (up to ${LB_WAIT_SECS}s)..."

# Known service names from the Helm charts/modules:
ARGOCD_SVC="${ARGOCD_SVC:-argo-cd-argocd-server}"
JENKINS_SVC="${JENKINS_SVC:-jenkins}"

# Poll loops
end_time=$(( $(date +%s) + LB_WAIT_SECS ))

ARGOCD_ADDR=""
JENKINS_ADDR=""

while [ "$(date +%s)" -lt "$end_time" ]; do
  # Fetch addresses if not already captured
  if [ -z "$ARGOCD_ADDR" ]; then
    ARGOCD_ADDR="$(get_svc_addr "$ARGOCD_NS" "$ARGOCD_SVC")"
  fi
  if [ -z "$JENKINS_ADDR" ]; then
    JENKINS_ADDR="$(get_svc_addr "$JENKINS_NS" "$JENKINS_SVC")"
  fi

  # If both resolved, stop waiting
  if [ -n "$ARGOCD_ADDR" ] && [ -n "$JENKINS_ADDR" ]; then
    break
  fi

  sleep "$LB_POLL_SECS"
done

# Compose URLs from discovered addresses
ARGOCD_URL=""
JENKINS_URL=""

if [ -n "$ARGOCD_ADDR" ]; then
  ARGOCD_URL="http://${ARGOCD_ADDR}"
fi
if [ -n "$JENKINS_ADDR" ]; then
  JENKINS_URL="http://${JENKINS_ADDR}"
fi

# Fallback: read from Terraform outputs if still empty
if [ -z "$ARGOCD_URL" ]; then
  ARGOCD_URL="$(terraform -chdir="$TF_DIR" output -raw argocd_url 2>/dev/null || true)"
fi
if [ -z "$JENKINS_URL" ]; then
  JENKINS_URL="$(terraform -chdir="$TF_DIR" output -raw jenkins_url 2>/dev/null || true)"
fi

echo "✅ Deploy complete."
echo "   - EKS cluster: $CLUSTER_NAME ($AWS_REGION)"
echo "   - Jenkins credential 'github-token' created in namespace '$JENKINS_NS'."
echo "   - Your pipeline can now push using credentialsId = 'github-token'."

# Print URLs if available
if [ -n "$ARGOCD_URL" ]; then
  echo "🌐 Argo CD UI:     $ARGOCD_URL"
else
  echo "🌐 Argo CD UI:     (pending — LoadBalancer not ready yet)"
fi

if [ -n "$JENKINS_URL" ]; then
  echo "🧰 Jenkins UI:     $JENKINS_URL"
else
  echo "🧰 Jenkins UI:     (pending — LoadBalancer not ready yet)"
fi
