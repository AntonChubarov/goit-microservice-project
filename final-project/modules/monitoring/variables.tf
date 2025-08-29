variable "grafana_admin_password" {
  description = "Grafana admin password for kube-prometheus-stack (grafana.adminPassword)"
  type        = string
  sensitive   = true
  default     = "GrafanaPassw0rd!" # change via -var or TF_VAR_grafana_admin_password if you wire it through the root
}
