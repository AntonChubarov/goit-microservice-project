variable "cluster_name" {
  type = string
}

variable "namespace" {
  type    = string
  default = "jenkins"
}

variable "chart_version" {
  type    = string
  default = "5.8.27"
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}
