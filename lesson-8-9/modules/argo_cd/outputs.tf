data "kubernetes_service_v1" "argocd_server" {
  provider = kubernetes.eks
  metadata {
    name      = "argo-cd-argocd-server"
    namespace = var.namespace
  }
  depends_on = [helm_release.argo_cd]
}

locals {
  argocd_lb = try(
    data.kubernetes_service_v1.argocd_server.status[0].load_balancer[0].ingress[0].hostname,
    try(data.kubernetes_service_v1.argocd_server.status[0].load_balancer[0].ingress[0].ip, null)
  )
}

output "argocd_hostname" {
  value = local.argocd_lb
}

output "argocd_url" {
  value = local.argocd_lb != null ? "http://${local.argocd_lb}" : null
}
