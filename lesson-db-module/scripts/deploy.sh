#!/bin/sh
set -eu
# POSIX-only: no pipefail

# ==========================================================
# deploy.sh (idempotent)
# - Base infra (VPC/ECR/EKS)
# - Build & push Django image
# - Update REMOTE chart values.yaml (image.* always; DB envs optional)
# - Full Terraform apply (Jenkins, Argo CD, etc.)
# - Print service URLs
#
# Usage:
#   GITHUB_USERNAME=... GITHUB_TOKEN=... ./scripts/deploy.sh
#
# Flags (optional):
#   UPDATE_REMOTE_DB_VALUES=true   # also write DB envs to remote chart (requires yq; beware secrets!)
#
# Notes:
#   - Region pinned to us-east-1.
#   - DB updates pull from Terraform outputs when available.
# ==========================================================

: "${GITHUB_USERNAME:?Set GITHUB_USERNAME, e.g. GITHUB_USERNAME=me}"
: "${GITHUB_TOKEN:?Set GITHUB_TOKEN, e.g. GITHUB_TOKEN=ghp_xxx}"

REGION="us-east-1"
export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"

GITHUB_REPO_URL="https://github.com/AntonChubarov/goit-microservice-project.git"
GITHUB_BRANCH="lesson-db-module"

UPDATE_REMOTE_DB_VALUES="${UPDATE_REMOTE_DB_VALUES:-false}"   # default: don't commit DB secrets to Git

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found"; exit 1; }; }
need docker
need terraform
need aws
need kubectl
need helm
need git
# yq optional; used when present

mask() { printf "%s" "$1" | sed 's/./*/g'; }

# Make TF know GH creds and region
export TF_VAR_github_user="$GITHUB_USERNAME"
export TF_VAR_github_pat="$GITHUB_TOKEN"
export TF_VAR_github_repo_url="$GITHUB_REPO_URL"
export TF_VAR_region="$REGION"

# Non-interactive default; override by exporting TF_VAR_rds_password
export TF_VAR_rds_password="${TF_VAR_rds_password:-SamplePassw0rd123!}"

echo "== Region: ${REGION} =="
echo "== Using TF_VAR_rds_password (hidden) =="

# Helper: safe terraform output
tf_out() { terraform -chdir="${ROOT_DIR}" output -raw "$1" 2>/dev/null || true; }

# ----------------------------------------------------------
# 0) Terraform init
# ----------------------------------------------------------
echo "== Terraform init =="
terraform -chdir="${ROOT_DIR}" init -upgrade

# ----------------------------------------------------------
# 1) Base infra (VPC/ECR/EKS)
# ----------------------------------------------------------
echo "== Terraform apply (base infra: VPC/ECR/EKS) =="
terraform -chdir="${ROOT_DIR}" apply -auto-approve \
  -target=module.vpc \
  -target=module.ecr \
  -target=module.eks

ECR_REPO_URL="$(tf_out ecr_repository_url)"
EKS_CLUSTER_NAME="$(tf_out eks_cluster_name)"
[ -n "${ECR_REPO_URL}" ] || { echo "ERROR: ECR repository URL output is empty"; exit 1; }

# ----------------------------------------------------------
# 2) Build & push image
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
# 3) Update REMOTE chart values.yaml (image.* always; DB envs optional)
# ----------------------------------------------------------
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT INT HUP

echo "== Cloning ${GITHUB_REPO_URL} (${GITHUB_BRANCH}) =="
git -C "${TMP_DIR}" clone \
  "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/AntonChubarov/goit-microservice-project.git" repo >/dev/null 2>&1
cd "${TMP_DIR}/repo"
git checkout "${GITHUB_BRANCH}"

VALUES_FILE="lesson-db-module/charts/django-app/values.yaml"
[ -f "${VALUES_FILE}" ] || { echo "ERROR: ${VALUES_FILE} not found in remote repo"; exit 1; }

# Updater: image.repository & image.tag
update_image_fields_with_yq() {
  yq -i ".image.repository = \"${ECR_REPO_URL}\" | .image.tag = \"latest\"" "${VALUES_FILE}"
}
update_image_fields_with_awk() {
  # Only touch keys under the first 'image:' mapping
  awk -v repo="${ECR_REPO_URL}" -v tag="latest" '
    BEGIN{in_image=0}
    /^image:[[:space:]]*$/ {in_image=1; print; next}
    in_image==1 && /^[^[:space:]]/ {in_image=0}  # left image block
    {
      if (in_image==1 && $1 ~ /^[[:space:]]*repository:/) {
        sub(/repository:.*/,"repository: "repo)
      } else if (in_image==1 && $1 ~ /^[[:space:]]*tag:/) {
        sub(/tag:.*/,"tag: "tag)
      }
      print
    }
  ' "${VALUES_FILE}" > "${VALUES_FILE}.tmp" && mv "${VALUES_FILE}.tmp" "${VALUES_FILE}"
}

if command -v yq >/dev/null 2>&1; then
  update_image_fields_with_yq
else
  echo "(!) yq not found; using awk fallback for image.repository/tag"
  update_image_fields_with_awk
fi

# Optional: update DB envs in remote chart (beware secrets!)
if [ "${UPDATE_REMOTE_DB_VALUES}" = "true" ]; then
  if ! command -v yq >/dev/null 2>&1; then
    echo "WARNING: UPDATE_REMOTE_DB_VALUES=true but 'yq' is not installed; skipping DB env updates."
  else
    echo "== (Optional) Creating/reading RDS to populate DB envs =="
    # Make sure RDS exists to fetch outputs (idempotent)
    terraform -chdir="${ROOT_DIR}" apply -auto-approve -target=module.rds || true

    RDS_HOST="$(tf_out rds_host)"; [ -z "$RDS_HOST" ] && RDS_HOST="$(tf_out rds_endpoint)"; [ -z "$RDS_HOST" ] && RDS_HOST="$(tf_out rds_address)"
    RDS_DB="$(tf_out rds_db_name)"; [ -z "$RDS_DB" ] && RDS_DB="django_db"
    RDS_USER="$(tf_out rds_username)"; [ -z "$RDS_USER" ] && RDS_USER="django_user"
    RDS_PASS="${TF_VAR_rds_password}"

    if [ -z "$RDS_HOST" ]; then
      echo "WARNING: Could not resolve RDS host output; skipping DB env updates."
    else
      DB_URL="postgres://${RDS_USER}:${RDS_PASS}@${RDS_HOST}:5432/${RDS_DB}"
      echo "== Updating remote chart DB envs (host=${RDS_HOST}, db=${RDS_DB}, user=${RDS_USER}, pass=$(mask "${RDS_PASS}")) =="

      yq -i "
        .config.POSTGRES_HOST = \"${RDS_HOST}\" |
        .config.POSTGRES_PORT = \"5432\" |
        .config.POSTGRES_USER = \"${RDS_USER}\" |
        .config.POSTGRES_NAME = \"${RDS_DB}\" |
        .config.POSTGRES_PASSWORD = \"${RDS_PASS}\" |
        .config.POSTGRES_URL = \"${DB_URL}\" |
        .config.DATABASE_URL = \"${DB_URL}\"
      " "${VALUES_FILE}"
    fi
  fi
else
  echo "== Skipping DB env updates to remote chart (UPDATE_REMOTE_DB_VALUES=false) =="
fi

git config user.email "cicd-bot@example.local"
git config user.name  "cicd-bot"
git add "${VALUES_FILE}"

if ! git diff --quiet --cached; then
  MSG="ci: update image repo/tag"
  [ "${UPDATE_REMOTE_DB_VALUES}" = "true" ] && MSG="${MSG} and DB envs"
  git commit -m "${MSG}"
  git push origin "${GITHUB_BRANCH}"
  echo "== Pushed changes to ${GITHUB_BRANCH} =="
else
  echo "== No changes in ${VALUES_FILE}; skipping commit/push =="
fi

cd "${ROOT_DIR}"

# ----------------------------------------------------------
# 4) Full Terraform apply (Jenkins, Argo CD, addons, etc.)
# ----------------------------------------------------------
echo "== Terraform apply (full stack) =="
terraform -chdir="${ROOT_DIR}" apply -auto-approve

# ----------------------------------------------------------
# 5) Print URLs from Terraform outputs
# ----------------------------------------------------------
echo "================ Service URLs (from Terraform outputs) ================"
echo "Jenkins: $(terraform -chdir="${ROOT_DIR}" output -raw jenkins_url || echo '(unavailable)')"
echo "Argo CD: $(terraform -chdir="${ROOT_DIR}" output -raw argocd_url || echo '(unavailable)')"

echo "Argo CD admin password command:"
terraform -chdir="${ROOT_DIR}" output -raw argocd_admin_password || true

echo "✅ Deployment complete. Region=${REGION}. ECR image pushed as: ${ECR_REPO_URL}:latest and :${IMAGE_TAG}"
