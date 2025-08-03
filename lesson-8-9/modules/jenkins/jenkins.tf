resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = var.namespace
    labels = {
      "pod-security.kubernetes.io/enforce"         = "privileged"
      "pod-security.kubernetes.io/enforce-version" = "latest"
    }
  }
}

resource "kubernetes_storage_class_v1" "ebs_sc" {
  metadata {
    name = "ebs-sc"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner = "kubernetes.io/aws-ebs"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters          = { type = "gp2" }   # gp2 works everywhere
}

resource "helm_release" "jenkins" {
  name             = "jenkins"
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false

  wait    = false
  timeout = 900

  values = [file("${path.module}/values.yaml")]

  depends_on = [
    kubernetes_service_account.jenkins_sa,
    kubernetes_storage_class_v1.ebs_sc
  ]
}
