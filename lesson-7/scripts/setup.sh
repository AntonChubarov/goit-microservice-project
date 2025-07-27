#!/bin/sh
set -eu

# ======== Configuration ==========
AWS_REGION="us-east-1"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DOCKERFILE_PATH="$PROJECT_ROOT/../Dockerfile"
DOCKER_CONTEXT="$(dirname "$DOCKERFILE_PATH")"

CHART_PATH="$PROJECT_ROOT/charts/django-app"
RELEASE_NAME="django-app"
METRICS_SERVER_NAME="metrics-server"
IMAGE_TAG="$(date +%Y%m%d%H%M%S)"
# =================================

cd "$PROJECT_ROOT"

# --- Preflight checks ---
if [ ! -f "$DOCKERFILE_PATH" ]; then
  echo "ERROR: Dockerfile not found at $DOCKERFILE_PATH" >&2
  exit 1
fi
if [ ! -f "$DOCKER_CONTEXT/requirements.txt" ]; then
  echo "ERROR: requirements.txt not found next to the Dockerfile at $DOCKER_CONTEXT" >&2
  echo "       Ensure requirements.txt is inside the Docker build context." >&2
  exit 1
fi

# Terraform setup
terraform init -upgrade
terraform apply -auto-approve

# Get Terraform outputs
ECR_REPO_URL="$(terraform output -raw ecr_repository_url)"
CLUSTER_NAME="$(terraform output -raw eks_cluster_name)"

DB_ENDPOINT="$(terraform output -raw db_endpoint)"
DB_PORT="$(terraform output -raw db_port)"
DB_NAME="$(terraform output -raw db_name)"
DB_USER="$(terraform output -raw db_username)"
DB_PASS="$(terraform output -raw db_password)"

# Update kubeconfig
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

# Install metrics-server
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo update
helm upgrade --install "$METRICS_SERVER_NAME" metrics-server/metrics-server -n kube-system --create-namespace

# Login to ECR
REGISTRY_HOST="$(echo "$ECR_REPO_URL" | cut -d'/' -f1)"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_HOST"

# Build and push Docker image
# IMPORTANT: use DOCKER_CONTEXT (the Dockerfile's directory), not PROJECT_ROOT
docker build -f "$DOCKERFILE_PATH" -t "$ECR_REPO_URL:$IMAGE_TAG" "$DOCKER_CONTEXT"
docker push "$ECR_REPO_URL:$IMAGE_TAG"

# Compose DATABASE_URL and set Helm secrets
DATABASE_URL="postgres://${DB_USER}:${DB_PASS}@${DB_ENDPOINT}:${DB_PORT}/${DB_NAME}"

helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
  --set image.repository="$ECR_REPO_URL" \
  --set image.tag="$IMAGE_TAG" \
  --set-string secrets.POSTGRES_DB="$DB_NAME" \
  --set-string secrets.POSTGRES_USER="$DB_USER" \
  --set-string secrets.POSTGRES_PASSWORD="$DB_PASS" \
  --set-string secrets.POSTGRES_HOST="$DB_ENDPOINT" \
  --set-string secrets.POSTGRES_PORT="$DB_PORT" \
  --set-string secrets.DATABASE_URL="$DATABASE_URL"

# Wait for LoadBalancer hostname
printf "Waiting for LoadBalancer hostname"
i=0
while [ "$i" -lt 60 ]; do
  HOSTNAME=$(kubectl get svc "$RELEASE_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$HOSTNAME" ]; then
    echo
    echo "Service hostname: $HOSTNAME"
    exit 0
  fi
  printf "."
  sleep 5
  i=$((i + 1))
done

echo
echo "Timed out waiting for LoadBalancer hostname"
