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

# --- Terraform apply ---
terraform -chdir="$TF_DIR" init -upgrade
terraform -chdir="$TF_DIR" apply -auto-approve

# --- Outputs ---
CLUSTER_NAME="$(terraform -chdir="$TF_DIR" output -raw eks_cluster_name)"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null

# --- Ensure namespaces exist ---
for ns in "$JENKINS_NS" "$ARGOCD_NS"; do
  i=0
  until kubectl get ns "$ns" >/dev/null 2>&1; do
    i=$((i+1))
    [ "$i" -gt 36 ] && { echo "ERROR: namespace '$ns' not found."; exit 1; }
    sleep 5
  done
done

# --- Adjust AWS EBS CSI node probes to avoid early readiness flaps ---
echo "⏳ Adjusting EBS CSI node probes to avoid early readiness flaps..."
kubectl -n kube-system patch ds ebs-csi-node --type=strategic -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "ebs-plugin",
            "livenessProbe":  {"initialDelaySeconds": 30, "periodSeconds": 10, "timeoutSeconds": 5, "failureThreshold": 5},
            "readinessProbe": {"initialDelaySeconds": 30, "periodSeconds": 10, "timeoutSeconds": 5, "failureThreshold": 5}
          }
        ]
      }
    }
  }
}' >/dev/null 2>&1 || true

# --- Wait for AWS EBS CSI node driver so PVCs can bind cleanly ---
echo "⏳ Waiting for EBS CSI node driver to be Ready (DaemonSet ebs-csi-node)..."
if ! kubectl -n kube-system rollout status ds/ebs-csi-node --timeout=6m; then
  echo "⚠️  EBS CSI node driver did not become Ready in time. Diagnostics:"
  kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver -o wide || true
  kubectl -n kube-system describe ds/ebs-csi-node || true
  # Do not hard-fail here; often it catches up in a minute. Jenkins may still start if PVC binds later.
fi

# --- Jenkins GitHub credential (k8s secret, consumed by credentials-provider) ---
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

# --- Quick egress check (plugin downloads need outbound internet) ---
cat <<'EOF' | kubectl apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: egress-check
  namespace: default
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: curl
          image: curlimages/curl:8.11.1
          command: ["/bin/sh","-lc"]
          args:
            - |
              echo "Checking https://updates.jenkins.io ..."
              if curl -sS --max-time 20 https://updates.jenkins.io/update-center.json >/dev/null; then
                echo "EGRESS_OK"
                exit 0
              else
                echo "EGRESS_FAIL"
                exit 1
              fi
  backoffLimit: 0
EOF

echo "⏳ Waiting for egress-check..."
if kubectl -n default wait --for=condition=complete job/egress-check --timeout=60s >/dev/null 2>&1; then
  :
else
  echo "⚠️  Egress check did not complete; fetching logs:"
fi
kubectl -n default logs job/egress-check || true
kubectl -n default delete job egress-check --ignore-not-found >/dev/null 2>&1 || true

echo "⏳ Waiting for LoadBalancer addresses (up to ${LB_WAIT_SECS}s)..."
get_svc_addr() {
  ns="$1"; name="$2"
  addr="$(kubectl -n "$ns" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "$addr" ] || addr="$(kubectl -n "$ns" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  printf "%s" "${addr}"
}

ARGOCD_SVC="${ARGOCD_SVC:-argo-cd-argocd-server}"
JENKINS_SVC="${JENKINS_SVC:-jenkins}"

end_time=$(( $(date +%s) + LB_WAIT_SECS ))
ARGOCD_ADDR=""; JENKINS_ADDR=""
while [ "$(date +%s)" -lt "$end_time" ]; do
  [ -n "$ARGOCD_ADDR" ] || ARGOCD_ADDR="$(get_svc_addr "$ARGOCD_NS" "$ARGOCD_SVC")"
  [ -n "$JENKINS_ADDR" ] || JENKINS_ADDR="$(get_svc_addr "$JENKINS_NS" "$JENKINS_SVC")"
  [ -n "$ARGOCD_ADDR" ] && [ -n "$JENKINS_ADDR" ] && break
  sleep "$LB_POLL_SECS"
done

ARGOCD_URL=""; JENKINS_URL=""
[ -n "$ARGOCD_ADDR" ] && ARGOCD_URL="http://${ARGOCD_ADDR}"
[ -n "$JENKINS_ADDR" ] && JENKINS_URL="http://${JENKINS_ADDR}"

[ -n "$ARGOCD_URL" ] || ARGOCD_URL="$(terraform -chdir="$TF_DIR" output -raw argocd_url 2>/dev/null || true)"
[ -n "$JENKINS_URL" ] || JENKINS_URL="$(terraform -chdir="$TF_DIR" output -raw jenkins_url 2>/dev/null || true)"

echo "✅ Deploy complete."
echo "   - EKS cluster: $CLUSTER_NAME ($AWS_REGION)"
echo "   - Jenkins credential 'github-token' created in '$JENKINS_NS'."
[ -n "$JENKINS_URL" ] && echo "🧰 Jenkins UI:     $JENKINS_URL" || echo "🧰 Jenkins UI:     (pending — LoadBalancer not ready yet)"
[ -n "$ARGOCD_URL" ] && echo "🌐 Argo CD UI:     $ARGOCD_URL" || echo "🌐 Argo CD UI:     (pending — LoadBalancer not ready yet)"

echo "ℹ️  If Jenkins still shows 503 for a while, that's normal during first boot."
echo "    It should stabilize once plugins and JCasC load."
