#!/bin/sh
set -eu

# --- Resolve paths relative to this script ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"   # points to lesson-8-9
JENKINS_NS="${JENKINS_NS:-jenkins}"
AWS_REGION="${AWS_REGION:-us-east-1}"

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

echo "✅ Deploy complete."
echo "   - EKS cluster: $CLUSTER_NAME ($AWS_REGION)"
echo "   - Jenkins credential 'github-token' created in namespace '$JENKINS_NS'."
echo "   - Your pipeline can now push using credentialsId = 'github-token'."
