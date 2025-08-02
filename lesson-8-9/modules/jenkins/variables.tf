variable "cluster_name" {
  type = string
}

variable "namespace" {
  type    = string
  default = "jenkins"
}

variable "chart_version" {
  type    = string
  default = "5.2.0"
}
