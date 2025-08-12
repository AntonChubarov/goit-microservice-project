#!/bin/sh
set -eu

# --- Resolve paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

JENKINS_NS="${JENKINS_NS:-jenkins}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Wait controls for LoadBalancer provisioning
LB_WAIT_SECS="${LB_WAIT_SECS:-480}"
LB_POLL_SECS="${LB_POLL_SECS:-10}"

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

export GITHUB_USERNAME GITHUB_TOKEN

# --- Terraform apply ---
terraform -chdir="$TF_DIR" init -upgrade
terraform -chdir="$TF_DIR" apply -auto-approve

# --- Update kubeconfig for the created/updated cluster ---
if command -v aws >/dev/null 2>&1; then
  EKS_CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw eks_cluster_name)"
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME" >/dev/null
fi

# --- Helper: print service URL once LB is up ---
print_svc_url () {
  _ns="$1"; _svc="$2"
  echo "Waiting for LoadBalancer for ${_svc} in ${_ns} ..."
  SECS=0
  while [ $SECS -lt "$LB_WAIT_SECS" ]; do
    if EXTERNAL_HOST="$(kubectl -n "$_ns" get svc "$_svc" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"; then
      if [ -n "${EXTERNAL_HOST:-}" ] && [ "$EXTERNAL_HOST" != "<pending>" ]; then
        echo "https://${EXTERNAL_HOST}"
        return 0
      fi
    fi
    SECS=$((SECS + LB_POLL_SECS))
    sleep "$LB_POLL_SECS"
  done
  echo "(LoadBalancer for ${_svc} not ready after ${LB_WAIT_SECS}s)"
  return 1
}

# --- Print URLs ---
echo "\n== URLs =="
echo "Jenkins: $(print_svc_url "$JENKINS_NS" jenkins || true)"
echo "Argo CD: $(print_svc_url "$ARGOCD_NS" argocd-server || true)"
echo "== End URLs ==\n"

# --- New: Jenkins diagnostics (init container logs) ---
say() { printf '%s\n' "$*"; }

find_jenkins_pod () {
  # Try common selectors used by the official chart
  kubectl -n "$JENKINS_NS" get pods -l app.kubernetes.io/component=jenkins-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
  kubectl -n "$JENKINS_NS" get pods -l app.kubernetes.io/instance=jenkins -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

dump_jenkins_init_logs () {
  POD="$(find_jenkins_pod)"
  if [ -z "${POD:-}" ]; then
    say "Jenkins pod not found in namespace ${JENKINS_NS}"
    return 0
  fi

  say "\n== Jenkins pod: ${POD} =="
  kubectl -n "$JENKINS_NS" get pod "$POD" -o wide || true

  INIT_LIST="$(kubectl -n "$JENKINS_NS" get pod "$POD" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null || true)"
  if [ -n "${INIT_LIST:-}" ]; then
    say "\n== Init containers =="
    for c in $INIT_LIST; do
      say "\n--- logs (init container: $c) ---"
      kubectl -n "$JENKINS_NS" logs "$POD" -c "$c" --tail=200 || true
    done
  else
    say "No init containers reported."
  fi

  say "\n--- logs (main container: jenkins, last 300 lines) ---"
  kubectl -n "$JENKINS_NS" logs "$POD" -c jenkins --tail=300 || true

  say "\n--- describe pod (events) ---"
  kubectl -n "$JENKINS_NS" describe pod "$POD" || true
}

# Give the pod a little time to appear, then always dump init logs to help debugging
sleep 20
dump_jenkins_init_logs

echo "\nDeployment complete."
