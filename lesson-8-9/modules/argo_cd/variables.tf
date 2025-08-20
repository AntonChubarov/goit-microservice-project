variable "name" {
  description = "Назва Helm-релізу"
  type        = string
  default     = "argo-cd"
}

variable "namespace" {
  description = "K8s namespace для Argo CD"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Версія Argo CD чарта"
  type        = string
  default     = "5.46.4"
}

# NEW: values used to template charts/values.yaml -> Repository Secret + Application source
variable "github_user" {
  description = "GitHub username for Argo CD repository credential"
  type        = string
}

variable "github_pat" {
  description = "GitHub PAT (password) for Argo CD repository credential"
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "GitHub repository URL (e.g. https://github.com/AntonChubarov/goit-microservice-project.git)"
  type        = string
}
