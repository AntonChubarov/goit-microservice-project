resource "helm_release" "argo_cd" {
  name         = var.name
  namespace    = var.namespace
  repository   = "https://argoproj.github.io/argo-helm"
  replace      = true
  force_update = true
  chart        = "argo-cd"
  version      = var.chart_version

  values = [
    file("${path.module}/values.yaml")
  ]

  create_namespace = true
}

locals {
  # rds_endpoint often includes :5432; we only want the hostname
  rds_host = split(":", var.rds_endpoint)[0]

  # IMPORTANT: render charts/values.yaml and provide ALL placeholders it references
  rendered_values = templatefile("${path.module}/charts/values.yaml", {
    rds_host        = local.rds_host
    rds_username    = var.rds_username
    rds_db_name     = var.rds_db_name
    rds_password    = var.rds_password
    github_repo_url = var.github_repo_url
    github_user     = var.github_user
    github_pat      = var.github_pat
  })
}

resource "helm_release" "argo_apps" {
  name              = "${var.name}-apps"
  chart             = "${path.module}/charts"
  namespace         = var.namespace
  create_namespace  = false
  dependency_update = true

  values     = [local.rendered_values]
  depends_on = [helm_release.argo_cd]
}
