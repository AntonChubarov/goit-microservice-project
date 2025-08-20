#!/bin/sh
set -eu
# POSIX-only: no "pipefail"

# ==========================================================
# deploy.sh
# 1) Create base infra (VPC, ECR, EKS) with Terraform targets
# 2) Build Django image locally from ./django and push to ECR (latest + timestamp)
# 3) Apply full Terraform (Jenkins, Argo CD, etc.)
# 4) Install metrics-server and print LB URLs
#
# Usage:
#   GITHUB_USERNAME=... GITHUB_TOKEN=... ./scripts/deploy.sh
# ==========================================================

# ---- required envs ----
: "${GITHUB_USERNAME:?Set GITHUB_USERNAME, e.g. GITHUB_USERNAME=me}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN, e.g. GITHUB_TOKEN=ghp_xxx}"

# ---- fixed region (as requested) ----
REGION="us-east-1"
export AWS_REGION="${REGION}"
export AWS_DEFAULT_REGION="${REGION}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# Paths for local Django build
DOCKER_CONTEXT="${ROOT_DIR}/django"
DOCKERFILE_PATH="${DOCKER_CONTEXT}/Dockerfile"

if [ ! -f "${DOCKERFILE_PATH}" ]; then
  echo "ERROR: Dockerfile not found at ${DOCKERFILE_PATH}"
  exit 1
fi

# Tool checks
if ! command -v docker >/dev/null 2>&1; then echo "ERROR: docker CLI not found"; exit 1; fi
if ! command -v terraform >/dev/null 2>&1; then echo "ERROR: terraform CLI not found"; exit 1; fi
if ! command -v aws >/dev/null 2>&1; then echo "ERROR: aws CLI not found"; exit 1; fi

# ---- derive repo URL for Argo/Jenkins secrets (prefer HTTPS) ----
ORIGIN_URL="$(git -C "${ROOT_DIR}" remote get-url origin 2>/dev/null || true)"
to_https() {
  case "$1" in
    git@github.com:*) printf '%s\n' "https://github.com/${1#git@github.com:}" ;;
    https://github.com/*|http://github.com/*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
GITHUB_REPO_URL="$(to_https "${ORIGIN_URL}")"

# Make them visible to Terraform
export TF_VAR_github_user="${GITHUB_USERNAME}"
export TF_VAR_github_pat="${GITHUB_TOKEN}"
export TF_VAR_github_repo_url="${GITHUB_REPO_URL}"

echo "== Region: ${REGION} =="

# ----------------------------------------------------------
# 0) Terraform init
# ----------------------------------------------------------
echo "== Terraform init =="
terraform -chdir="${ROOT_DIR}" init -upgrade

# ----------------------------------------------------------
# 1) Base infra only (VPC + ECR + EKS) so we can push image
# ----------------------------------------------------------
echo "== Terraform apply (base infra: VPC/ECR/EKS) =="
terraform -chdir="${ROOT_DIR}" apply -auto-approve \
  -target=module.vpc \
  -target=module.ecr \
  -target=module.eks

# Pull outputs we need
ECR_REPO_URL="$(terraform -chdir="${ROOT_DIR}" output -raw ecr_repository_url)"
EKS_CLUSTER_NAME="$(terraform -chdir="${ROOT_DIR}" output -raw eks_cluster_name)"

if [ -z "${ECR_REPO_URL}" ]; then
  echo "ERROR: ECR repository URL output is empty"
  exit 1
fi

# ----------------------------------------------------------
# 2) Build & push initial Django image (latest + timestamp)
# ----------------------------------------------------------
echo "== Docker login to ECR (${REGION}) =="
REGISTRY_HOST="$(printf "%s" "${ECR_REPO_URL}" | cut -d'/' -f1)"
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY_HOST}"

IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
echo "== Building image from ${DOCKER_CONTEXT} =="
docker build -f "${DOCKERFILE_PATH}" \
  -t "${ECR_REPO_URL}:latest" \
  -t "${ECR_REPO_URL}:${IMAGE_TAG}" \
  "${DOCKER_CONTEXT}"

echo "== Pushing ${ECR_REPO_URL}:latest =="
docker push "${ECR_REPO_URL}:latest"
echo "== Pushing ${ECR_REPO_URL}:${IMAGE_TAG} =="
docker push "${ECR_REPO_URL}:${IMAGE_TAG}"

echo "${IMAGE_TAG}" > "${ROOT_DIR}/.initial_image_tag"
echo "Wrote initial image tag to ${ROOT_DIR}/.initial_image_tag"

# ----------------------------------------------------------
# 3) Full Terraform (Jenkins, Argo CD, CSI addons, etc.)
# ----------------------------------------------------------
echo "== Terraform apply (full stack) =="
terraform -chdir="${ROOT_DIR}" apply -auto-approve

# ----------------------------------------------------------
# 4) Kubeconfig, metrics-server, readiness checks, URLs
# ----------------------------------------------------------
echo "== Update kubeconfig for ${EKS_CLUSTER_NAME} =="
aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}" >/dev/null

echo "== Install/upgrade metrics-server =="
if ! helm repo list 2>/dev/null | grep -q metrics-server; then
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server >/dev/null
fi
helm repo update >/dev/null
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --create-namespace >/dev/null

# Wait for Jenkins controller
JENKINS_NS="jenkins"
echo "== Waiting for Jenkins rollout =="
if ! kubectl -n "${JENKINS_NS}" rollout status statefulset/jenkins --timeout=15m; then
  echo "ERROR: Jenkins StatefulSet failed to roll out"
  POD="$(kubectl -n "${JENKINS_NS}" get pods -l app.kubernetes.io/component=jenkins-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -n "${POD}" ]; then
    kubectl -n "${JENKINS_NS}" describe pod "${POD}" || true
    kubectl -n "${JENKINS_NS}" logs "${POD}" -c jenkins --tail=200 || true
  fi
  exit 1
fi

# In-cluster HTTP probe (service listens on 80 per chart values)
echo "== Verifying Jenkins in-cluster HTTP =="
kubectl -n "${JENKINS_NS}" run jx-http-check --rm -i --restart=Never --image=curlimages/curl:8.8.0 -- \
  sh -lc 'for i in $(seq 1 60); do c=$(curl -s -o /dev/null -w "%{http_code}" http://jenkins.jenkins.svc.cluster.local/login); case "$c" in 200|302|403) echo "HTTP $c"; exit 0;; esac; sleep 5; done; echo TIMEOUT; exit 1'

print_lb() {
  NS="$1"; SVC="$2"; SCHEME="$3" # http or https
  echo "Waiting for ${SVC}.${NS} LoadBalancer..."
  i=1
  while [ "$i" -le 60 ]; do
    HN="$(kubectl -n "${NS}" get svc "${SVC}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname]' 2>/dev/null || true)"
    IP="$(kubectl -n "${NS}" get svc "${SVC}" -o jsonpath='{.status.loadBalancer.ingress[0].ip]' 2>/dev/null || true)"
    if [ -n "${HN}" ] && [ "${HN}" != "<pending>" ]; then
      echo "${SCHEME}://${HN}"
      return 0
    fi
    if [ -n "${IP}" ]; then
      echo "${SCHEME}://${IP}"
      return 0
    fi
    i=$((i+1))
    sleep 5
  done
  echo "(still pending)"
  return 1
}

echo "== Service URLs =="
JENKINS_URL="$(print_lb jenkins jenkins http | tail -n1)"
ARGO_URL="$(print_lb argocd argocd-server https | tail -n1)"
echo "Jenkins: ${JENKINS_URL}"
echo "Argo CD: ${ARGO_URL}"

# Helpful hint to fetch Argo CD admin password (module outputs a ready-to-run command)
echo "Argo CD admin password command:"
terraform -chdir="${ROOT_DIR}" output -raw argocd_admin_password || true

echo "✅ Deployment complete. Region=${REGION}. ECR image pushed as: ${ECR_REPO_URL}:latest and :${IMAGE_TAG}"
