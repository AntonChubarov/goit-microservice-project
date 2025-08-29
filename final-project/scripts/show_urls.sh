#!/bin/sh
set -eu

# Show external URLs for Argo CD, Jenkins, Grafana, and the Django app.
# Usage:
#   ./scripts/show_urls.sh
#
# Assumptions:
# - Default AWS profile is configured and has access to the cluster.
# - Terraform outputs include 'eks_cluster_name'.
# - Argo CD service may NOT be literally 'argocd-server' (chart templating varies).
#   We auto-detect by labels and fall back to common names; also try Ingress.
# - Grafana (kube-prometheus-stack) may expose via LoadBalancer or Ingress.
#   We auto-detect by labels and fall back to common names.

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
  # prefer hostname, then ip
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

# Helper: print ingress URL (scheme + hostname/ip or spec.rules host) or "(pending)"
ing_url() {
  ns="$1"; ing="$2"; scheme="$3"
  host="$(kubectl -n "$ns" get ingress "$ing" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  ip="$(kubectl -n "$ns" get ingress "$ing" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  rule_host="$(kubectl -n "$ns" get ingress "$ing" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
  if [ -n "${host}" ] && [ "${host}" != "<pending>" ]; then
    printf "%s://%s\n" "${scheme}" "${host}"
  elif [ -n "${ip}" ]; then
    printf "%s://%s\n" "${scheme}" "${ip}"
  elif [ -n "${rule_host}" ]; then
    printf "%s://%s\n" "${scheme}" "${rule_host}"
  else
    printf "(pending)\n"
  fi
}

# ---------- Jenkins (http) ----------
detect_jenkins_svc() {
  ns="jenkins"
  # Try label selector first
  name="$(kubectl -n "$ns" get svc -l app.kubernetes.io/name=jenkins \
          -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}' 2>/dev/null || true)"
  if [ -n "$name" ]; then printf "%s" "$name"; return 0; fi
  # Fallback to common name
  if kubectl -n "$ns" get svc jenkins >/dev/null 2>&1; then printf "jenkins"; return 0; fi
  printf ""
}
JENKINS_SVC="$(detect_jenkins_svc)"
JENKINS_URL="$( [ -n "$JENKINS_SVC" ] && svc_url jenkins "$JENKINS_SVC" http || printf "(pending)\n" )"

# ---------- Argo CD (https) ----------
detect_argocd_svc() {
  ns="argocd"
  # Prefer the canonical label for the server component
  name="$(kubectl -n "$ns" get svc -l app.kubernetes.io/name=argocd-server \
          -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}' 2>/dev/null || true)"
  if [ -n "$name" ]; then printf "%s" "$name"; return 0; fi
  # Otherwise, any LB service that belongs to Argo CD
  name="$(kubectl -n "$ns" get svc -l app.kubernetes.io/part-of=argocd \
          -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}' 2>/dev/null || true)"
  if [ -n "$name" ]; then printf "%s" "$name"; return 0; fi
  # Fallback to common names
  for n in argocd-server argo-cd-argocd-server argo-cd-server argocd; do
    if kubectl -n "$ns" get svc "$n" >/dev/null 2>&1; then printf "%s" "$n"; return 0; fi
  done
  printf ""
}

ARGO_URL=""
ARGO_SVC="$(detect_argocd_svc)"
if [ -n "$ARGO_SVC" ]; then
  ARGO_URL="$(svc_url argocd "$ARGO_SVC" https)"
fi

# If still pending/empty, try Ingress
if [ -z "$ARGO_URL" ] || [ "$ARGO_URL" = "(pending)" ]; then
  ing="$(kubectl -n argocd get ingress -l app.kubernetes.io/name=argocd-server \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -z "$ing" ]; then
    ing="$(kubectl -n argocd get ingress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  if [ -n "$ing" ]; then
    ARGO_URL="$(ing_url argocd "$ing" https)"
  else
    ARGO_URL="(pending)"
  fi
fi

# ---------- Grafana (http by default) ----------
detect_grafana_svc() {
  ns="monitoring"
  # kube-prometheus-stack exposes Grafana with label app.kubernetes.io/name=grafana
  name="$(kubectl -n "$ns" get svc -l app.kubernetes.io/name=grafana \
          -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}' 2>/dev/null || true)"
  if [ -n "$name" ]; then printf "%s" "$name"; return 0; fi
  # Fallback to common service names
  for n in kube-prometheus-stack-grafana grafana; do
    if kubectl -n "$ns" get svc "$n" >/dev/null 2>&1; then printf "%s" "$n"; return 0; fi
  done
  printf ""
}
GRAFANA_URL=""
GRAFANA_SVC="$(detect_grafana_svc)"
if [ -n "$GRAFANA_SVC" ]; then
  GRAFANA_URL="$(svc_url monitoring "$GRAFANA_SVC" http)"
fi

# If still pending/empty, try Grafana Ingress
if [ -z "$GRAFANA_URL" ] || [ "$GRAFANA_URL" = "(pending)" ]; then
  ing="$(kubectl -n monitoring get ingress -l app.kubernetes.io/name=grafana \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -z "$ing" ]; then
    # any ingress in monitoring (first)
    ing="$(kubectl -n monitoring get ingress -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  if [ -n "$ing" ]; then
    # scheme: default to http unless you terminate TLS at the ingress
    GRAFANA_URL="$(ing_url monitoring "$ing" http)"
  else
    [ -z "$GRAFANA_URL" ] && GRAFANA_URL="(pending)"
  fi
fi

# ---------- Django app (http) ----------
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

  # 3) any LoadBalancer svc in any namespace, excluding argocd/jenkins/system/monitoring namespaces
  line="$(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | grep -Ev '^(kube-system|kube-public|kube-node-lease|argocd|jenkins|monitoring) ' \
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
echo "Grafana : ${GRAFANA_URL}"
echo "Django  : ${DJANGO_URL}"
