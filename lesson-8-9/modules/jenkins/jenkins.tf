resource "helm_release" "jenkins" {
  provider         = helm.eks
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = true
  values           = [file("${path.module}/values.yaml")]
}
