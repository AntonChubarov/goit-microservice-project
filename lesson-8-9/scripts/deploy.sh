#!/bin/sh
set -eu
# POSIX-only: no pipefail

# ==========================================================
# deploy.sh
# 1) Create base infra (VPC, ECR, EKS) with Terraform targets
# 2) Build Django image locally from ./django and push to ECR (latest + timestamp)
# 3) Commit image repo/tag to the remote GitHub chart (lesson-8-9) and push
# 4) Apply full Terraform (Jenkins, Argo CD, etc.)
# 5) Print Jenkins/Argo CD LoadBalancer URLs and ArgoCD admin password hint
#
# Usage:
#   GITHUB_USERNAME=... GITHUB_TOKEN=... ./scripts/deploy.sh
#
# Notes:
#   - Default AWS profile must be configured; this script uses it implicitly.
#   - Region hardcoded to us-east-1 (per request).
# ==========================================================

# ---- required envs ----
: "${GITHUB_USERNAME:?Set GITHUB_USERNAME, e.g. GITHUB_USERNAME=me}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN, e.g. GITHUB_TOKEN=ghp_xxx}"

# ---- constants (per request) ----
REGION="us-east-1"
export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"

GITHUB_REPO_URL="https://github.com/AntonChubarov/goit-microservice-project.git"
GITHUB_BRANCH="lesson-8-9"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# Tool checks
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found"; exit 1; }; }
need docker
need terraform
need aws
need kubectl
need helm
need git
need sed

# Tell Terraform about GitHub creds/repo for Jenkins/Argo modules
export TF_VAR_github_user="$GITHUB_USERNAME"
export TF_VAR_github_pat="$GITHUB_TOKEN"
export TF_VAR_github_repo_url="$GITHUB_REPO_URL"
# Ensure region variable is us-east-1 if root module uses var.region
export TF_VAR_region="$REGION"

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

[ -n "${ECR_REPO_URL}" ] || { echo "ERROR: ECR repository URL output is empty"; exit 1; }

# ----------------------------------------------------------
# 2) Build & push initial Django image (latest + timestamp)
# ----------------------------------------------------------
DOCKER_CONTEXT="${ROOT_DIR}/django"
DOCKERFILE_PATH="${DOCKER_CONTEXT}/Dockerfile"
[ -f "${DOCKERFILE_PATH}" ] || { echo "ERROR: Dockerfile not found at ${DOCKERFILE_PATH}"; exit 1; }

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
# 3) Update REMOTE GitHub chart values to use this ECR + latest
#     NOTE: all files live under the lesson-8-9/ folder
# ----------------------------------------------------------
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT INT HUP

echo "== Syncing chart values in ${GITHUB_REPO_URL} (${GITHUB_BRANCH}) =="
git -C "${TMP_DIR}" clone \
  "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/AntonChubarov/goit-microservice-project.git" repo >/dev/null 2>&1
cd "${TMP_DIR}/repo"
git checkout "${GITHUB_BRANCH}"

VALUES_FILE="lesson-8-9/charts/django-app/values.yaml"
[ -f "${VALUES_FILE}" ] || { echo "ERROR: ${VALUES_FILE} not found in remote repo"; exit 1; }

# Replace repository and tag lines in values.yaml
#   image:
#     repository: <ECR_REPO_URL>
#     tag: latest
sed -i.bak -E "s#^( *repository:).*#\1 ${ECR_REPO_URL}#" "${VALUES_FILE}"
sed -i.bak -E "s#^( *tag:).*#\1 latest#" "${VALUES_FILE}"
rm -f "${VALUES_FILE}.bak"

git config user.email "cicd-bot@example.local"
git config user.name  "cicd-bot"
git add "${VALUES_FILE}"
git commit -m "ci: point image to ${ECR_REPO_URL} and tag=latest (bootstrap deploy)"
git push origin "${GITHUB_BRANCH}"

cd "${ROOT_DIR}"

# ----------------------------------------------------------
# 4) Full Terraform apply (Jenkins, Argo CD, addons, etc.)
# ----------------------------------------------------------
echo "== Terraform apply (full stack) =="
terraform -chdir="${ROOT_DIR}" apply -auto-approve

# ----------------------------------------------------------
# 5) kubeconfig + print LB URLs + ArgoCD password hint
# ----------------------------------------------------------
echo "== Update kubeconfig for ${EKS_CLUSTER_NAME} =="
aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}" >/dev/null

print_lb() {
  NS="$1"; SVC="$2"; SCHEME="$3" # http or https
  echo "Waiting for ${SVC}.${NS} LoadBalancer..."
  i=1
  while [ "$i" -le 60 ]; do
    HN="$(kubectl -n "${NS}" get svc "${SVC}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
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

echo "Argo CD admin password command:"
terraform -chdir="${ROOT_DIR}" output -raw argocd_admin_password || true

echo "✅ Deployment complete. Region=${REGION}. ECR image pushed as: ${ECR_REPO_URL}:latest and :${IMAGE_TAG}"
