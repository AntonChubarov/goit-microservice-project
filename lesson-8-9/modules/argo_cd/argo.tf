resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.namespace
    labels = {
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
    }
  }
}

resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false

  wait    = false
  timeout = 900

  values = [file("${path.module}/values.yaml")]

  depends_on = [kubernetes_namespace.argocd]
}

resource "helm_release" "django_app" {
  name             = "django-app"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argocd-apps"
  version          = var.apps_chart_version
  namespace        = var.namespace
  create_namespace = false

  wait    = false
  timeout = 600

  values = [
    yamlencode({
      applications = [{
        name      = "django-app"
        namespace = var.namespace
        project   = "default"
        source = {
          repoURL        = var.repo_url
          targetRevision = var.revision
          path           = "lesson-8-9/charts/django-app"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "default"
        }
        syncPolicy = {
          automated  = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
        }
      }]
    })
  ]

  depends_on = [helm_release.argo_cd]
}
