#!/bin/sh
set -eu

# ======== Configuration ==========
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_NAME="django-app"
METRICS_SERVER_NAME="metrics-server"
# =================================

cd "$PROJECT_ROOT"

# Uninstall Helm releases (ignore errors)
helm uninstall "$RELEASE_NAME" >/dev/null 2>&1 || true
helm uninstall "$METRICS_SERVER_NAME" -n kube-system >/dev/null 2>&1 || true

# Destroy Terraform-managed resources
terraform destroy -auto-approve
