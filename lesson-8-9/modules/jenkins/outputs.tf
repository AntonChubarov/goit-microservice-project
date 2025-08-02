data "kubernetes_service_v1" "jenkins_svc" {
  provider = kubernetes.eks
  metadata {
    name      = "jenkins"
    namespace = var.namespace
  }
  depends_on = [helm_release.jenkins]
}

locals {
  jenkins_lb = try(
    data.kubernetes_service_v1.jenkins_svc.status[0].load_balancer[0].ingress[0].hostname,
    try(data.kubernetes_service_v1.jenkins_svc.status[0].load_balancer[0].ingress[0].ip, null)
  )
}

output "jenkins_hostname" {
  value = local.jenkins_lb
}

output "jenkins_url" {
  value = local.jenkins_lb != null ? "http://${local.jenkins_lb}" : null
}
