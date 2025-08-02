variable "cluster_name" {
  type = string
}

variable "namespace" {
  type    = string
  default = "argocd"
}

variable "chart_version" {
  type    = string
  default = "5.53.14"
}

variable "repo_url" {
  type = string
}

variable "revision" {
  type = string
}
