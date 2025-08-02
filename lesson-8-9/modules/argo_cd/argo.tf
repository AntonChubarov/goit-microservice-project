resource "kubernetes_namespace" "argocd" {
  provider = kubernetes.eks
  metadata { name = var.namespace }
}

resource "helm_release" "argo_cd" {
  provider         = helm.eks
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false
  values           = [file("${path.module}/values.yaml")]

  depends_on = [kubernetes_namespace.argocd]
}

resource "kubernetes_manifest" "django_app" {
  provider = kubernetes.eks
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "django-app"
      namespace = var.namespace
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.repo_url
        targetRevision = var.revision
        path           = "lesson-8-9/charts/django-app"
        helm           = { valueFiles = [] }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argo_cd]
}
