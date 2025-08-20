#!/bin/sh
set -eu
# POSIX-only: no pipefail

# ==========================================================
# deploy.sh
# 1) Create base infra (VPC, ECR, EKS) with Terraform targets
# 2) Build Django image locally from ./django and push to ECR (latest + timestamp)
# 3) Commit image repo/tag to the remote GitHub chart (lesson-8-9) and push
# 4) Apply full Terraform (Jenkins, Argo CD, etc.)
# 5) Wait for LB hostnames and print Jenkins & Argo CD URLs
# ==========================================================

: "${GITHUB_USERNAME:?Set GITHUB_USERNAME, e.g. GITHUB_USERNAME=me}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN, e.g. GITHUB_TOKEN=ghp_xxx}"

REGION="us-east-1"
export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"

GITHUB_REPO_URL="https://github.com/AntonChubarov/goit-microservice-project.git"
GITHUB_BRANCH="lesson-8-9"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found"; exit 1; }; }
need docker; need terraform; need aws; need kubectl; need helm; need git; need sed

export TF_VAR_github_user="$GITHUB_USERNAME"
export TF_VAR_github_pat="$GITHUB_TOKEN"
export TF_VAR_github_repo_url="$GITHUB_REPO_URL"
export TF_VAR_region="$REGION"

echo "== Region: ${REGION} =="

echo "== Terraform init =="
terraform -chdir="${ROOT_DIR}" init -upgrade

echo "== Terraform apply (base infra: VPC/ECR/EKS) =="
terraform -chdir="${ROOT_DIR}" apply -auto-approve \
  -target=module.vpc \
  -target=module.ecr \
  -target=module.eks

ECR_REPO_URL="$(terraform -chdir="${ROOT_DIR}" output -raw ecr_repository_url)"
EKS_CLUSTER_NAME="$(terraform -chdir="${ROOT_DIR}" output -raw eks_cluster_name)"
[ -n "${ECR_REPO_URL}" ] || { echo "ERROR: ECR repository URL output is empty"; exit 1; }

echo "== Docker login to ECR (${REGION}) =="
REGISTRY_HOST="$(printf "%s" "${ECR_REPO_URL}" | cut -d'/' -f1)"
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY_HOST}"

DOCKER_CONTEXT="${ROOT_DIR}/django"
DOCKERFILE_PATH="${DOCKER_CONTEXT}/Dockerfile"
[ -f "${DOCKERFILE_PATH}" ] || { echo "ERROR: Dockerfile not found at ${DOCKERFILE_PATH}"; exit 1; }

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

# Sync chart values in remote repo
TMP_DIR="$(mktemp -d)"; trap 'rm -rf "${TMP_DIR}"' EXIT INT HUP
echo "== Syncing chart values in ${GITHUB_REPO_URL} (${GITHUB_BRANCH}) =="
git -C "${TMP_DIR}" clone \
  "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/AntonChubarov/goit-microservice-project.git" repo >/dev/null 2>&1
cd "${TMP_DIR}/repo"
git checkout "${GITHUB_BRANCH}"

VALUES_FILE="lesson-8-9/charts/django-app/values.yaml"
[ -f "${VALUES_FILE}" ] || { echo "ERROR: ${VALUES_FILE} not found in remote repo"; exit 1; }
sed -i.bak -E "s#^( *repository:).*#\\1 ${ECR_REPO_URL}#" "${VALUES_FILE}"
sed -i.bak -E "s#^( *tag:).*#\\1 latest#" "${VALUES_FILE}"
rm -f "${VALUES_FILE}.bak"

git config user.email "cicd-bot@example.local"
git config user.name  "cicd-bot"
git add "${VALUES_FILE}"
if ! git diff --quiet --cached; then
  git commit -m "ci: point image to ${ECR_REPO_URL} and tag=latest (bootstrap deploy)"
  git push origin "${GITHUB_BRANCH}"
else
  echo "== No chart changes detected; skipping commit/push =="
fi
cd "${ROOT_DIR}"

echo "== Terraform apply (full stack) =="
terraform -chdir="${ROOT_DIR}" apply -auto-approve

# Make sure kubeconfig is set before polling services
aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}" >/dev/null

echo "== Waiting for LoadBalancer hostnames =="
wait_svc() {
  ns="$1"; name="$2"; tries="${3:-60}"; sleep_s="${4:-10}"
  i=0
  while [ $i -lt "$tries" ]; do
    host="$(kubectl -n "$ns" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    ip="$(kubectl -n "$ns" get svc "$name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    url="${host:-$ip}"
    if [ -n "$url" ]; then
      echo "$url"; return 0
    fi
    sleep "$sleep_s"; i=$((i+1))
  done
  echo ""
  return 1
}

JEN_URL_HOST="$(wait_svc jenkins jenkins 60 10 || true)"
ARGO_URL_HOST="$(wait_svc argocd argocd-server 60 10 || true)"

echo "================ Service URLs ================"
echo "Jenkins: ${JEN_URL_HOST:+http://$JEN_URL_HOST}"
echo "Argo CD: ${ARGO_URL_HOST:+http://$ARGO_URL_HOST}"

echo "Argo CD admin password command:"
terraform -chdir="${ROOT_DIR}" output -raw argocd_admin_password || true

echo "✅ Deployment complete. Region=${REGION}. Image pushed: ${ECR_REPO_URL}:latest and :${IMAGE_TAG}"
