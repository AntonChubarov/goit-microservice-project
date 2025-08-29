resource "helm_release" "kube-prometheus-stack" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "75.10.0"
  create_namespace = true

  values = [
    file("${path.module}/values.yaml")
  ]

  # Ensure Grafana admin password is set (securely)
  set_sensitive = [
    {
      name  = "grafana.adminPassword"
      value = var.grafana_admin_password
      # Optional but harmless; forces string type:
      # type  = "string"
    }
  ]
}
