#!/bin/sh
set -eu

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

EKS_CLUSTER_NAME="$(terraform output -raw eks_cluster_name)"
aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}"
