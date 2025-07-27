variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}
