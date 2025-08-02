resource "kubernetes_namespace" "argocd" {
  metadata { name = var.namespace }
}

resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = var.namespace
  create_namespace = false

  wait               = true
  timeout            = 900
  atomic             = false
  dependency_update  = true
  cleanup_on_fail    = false
  disable_openapi_validation = true

  values = [file("${path.module}/values.yaml")]

  depends_on = [kubernetes_namespace.argocd]
}

resource "helm_release" "django_app" {
  name             = "django-app"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argocd-apps"
  namespace        = var.namespace
  create_namespace = false

  wait               = true
  timeout            = 600
  atomic             = false
  dependency_update  = true
  disable_openapi_validation = true

  values = [
    yamlencode({
      applications = [
        {
          name      = "django-app"
          namespace = var.namespace
          project   = "default"
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
      ]
    })
  ]

  depends_on = [helm_release.argo_cd]
}
