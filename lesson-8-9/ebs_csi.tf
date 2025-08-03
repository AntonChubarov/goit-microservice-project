variable "enable_ebs_csi_driver" {
  type    = bool
  default = true
}

resource "helm_release" "aws_ebs_csi_driver" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  provider         = helm.eks
  name             = "aws-ebs-csi-driver"
  repository       = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart            = "aws-ebs-csi-driver"
  namespace        = "kube-system"
  create_namespace = false
  wait             = false
  timeout          = 300

  values = [
    yamlencode({
      controller = {
        serviceAccount = {
          create      = true
          name        = "ebs-csi-controller-sa"
          annotations = {
            "eks.amazonaws.com/role-arn" = module.eks.ebs_csi_irsa_role_arn
          }
        }
      }
    })
  ]

  depends_on = [module.eks]
}
