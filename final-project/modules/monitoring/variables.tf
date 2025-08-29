variable "grafana_admin_password" {
  description = "Grafana admin password for kube-prometheus-stack"
  type        = string
  sensitive   = true
}
