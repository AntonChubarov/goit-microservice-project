#!/bin/sh
# Show logs from the active django-app pod (name pattern "django-app-...").

set -eu

# Config
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
NAMESPACE="${NAMESPACE:-default}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$PROJECT_ROOT"

# Get cluster name from Terraform outputs and set kubeconfig
CLUSTER_NAME="$(terraform output -raw eks_cluster_name)"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null
