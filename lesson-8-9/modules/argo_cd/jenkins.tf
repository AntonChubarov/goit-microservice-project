resource "helm_release" "argocd" {
  provider         = helm.eks
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  values           = [file("${path.module}/values.yaml")]
}

resource "helm_release" "bootstrap" {
  provider          = helm.eks
  name              = "argocd-bootstrap"
  chart             = "${path.module}/charts"
  namespace         = var.namespace
  dependency_update = false
  values = [
    yamlencode({
      repoUrl  = var.repo_url
      revision = var.revision
    })
  ]
  depends_on = [helm_release.argocd]
}
