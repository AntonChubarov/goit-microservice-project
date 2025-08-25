resource "helm_release" "argo_cd" {
  name         = var.name
  namespace    = var.namespace
  repository   = "https://argoproj.github.io/argo-helm"
  chart        = "argo-cd"
  version      = var.chart_version
  replace      = true
  force_update = true
  create_namespace = true

  values = [
    file("${path.module}/values.yaml")
  ]
}

locals {
  # If rds_endpoint looks like "xxx.rds.amazonaws.com:5432", strip the port:
  rds_host = split(":", var.rds_endpoint)[0]

  # Render the apps-of-apps values with ALL placeholders required by the template.
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
