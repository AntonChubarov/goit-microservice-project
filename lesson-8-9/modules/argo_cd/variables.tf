variable "cluster_name" {
  type = string
}

variable "namespace" {
  type    = string
  default = "argocd"
}

variable "chart_version" {
  type    = string
  default = "6.7.17"
}

variable "repo_url" {
  type = string
}

variable "revision" {
  type    = string
  default = "main"
}
