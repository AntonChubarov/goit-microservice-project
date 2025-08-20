#!/bin/sh
set -eu

# Show external URLs for Argo CD, Jenkins, and the Django app.
# Usage:
#   ./scripts/show_urls.sh
#
# Assumptions:
# - Default AWS profile is configured and has access to the cluster.
# - Terraform outputs include 'eks_cluster_name'.
# - Argo CD service name:    argocd-server (ns: argocd)           -> https
# - Jenkins service name:    jenkins       (ns: jenkins)           -> http
# - Django app service:      autodetected (prefers ns: default)    -> http

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found in PATH" >&2; exit 1; }; }
need aws
need kubectl
need terraform

# Update kubeconfig for the current cluster
EKS_CLUSTER_NAME="$(terraform -chdir="${ROOT_DIR}" output -raw eks_cluster_name 2>/dev/null || true)"
if [ -n "${EKS_CLUSTER_NAME}" ]; then
  aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${REGION}" >/dev/null 2>&1 || true
fi

# Helper: print service URL (scheme + hostname/ip) or "(pending)"
svc_url() {
  ns="$1"; svc="$2"; scheme="$3"
  host="$(kubectl -n "$ns" get svc "$svc" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  ip="$(kubectl -n "$ns" get svc "$svc" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [ -n "${host}" ] && [ "${host}" != "<pending>" ]; then
    printf "%s://%s\n" "${scheme}" "${host}"
  elif [ -n "${ip}" ]; then
    printf "%s://%s\n" "${scheme}" "${ip}"
  else
    printf "(pending)\n"
  fi
}

# Jenkins (http)
JENKINS_URL="$(svc_url jenkins jenkins http)"

# Argo CD (https)
ARGO_URL="$(svc_url argocd argocd-server https)"

# Django app (http): try specific name first, then auto-detect in default ns, then any ns
detect_django_url() {
  # 1) common service name in default namespace
  url="$(svc_url default django-app http)"
  if [ "${url}" != "(pending)" ]; then
    printf "%s\n" "${url}"
    return 0
  fi

  # 2) any LoadBalancer svc in default namespace (first match)
  name="$(kubectl -n default get svc -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -n1 || true)"
  if [ -n "${name}" ]; then
    svc_url default "${name}" http
    return 0
  fi

  # 3) any LoadBalancer svc in any namespace, excluding argocd/jenkins/system namespaces
  #    pick the first one and assume it's the app
  line="$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | grep -Ev '^(kube-system|kube-public|kube-node-lease|argocd|jenkins) ' \
        | head -n1 || true)"
  ns="$(printf "%s" "${line}" | awk '{print $1}')"
  svc="$(printf "%s" "${line}" | awk '{print $2}')"
  if [ -n "${ns}" ] && [ -n "${svc}" ]; then
    svc_url "${ns}" "${svc}" http
    return 0
  fi

  printf "(pending)\n"
}

DJANGO_URL="$(detect_django_url)"

echo "================ Service URLs ================"
echo "Jenkins : ${JENKINS_URL}"
echo "Argo CD : ${ARGO_URL}"
echo "Django  : ${DJANGO_URL}"
