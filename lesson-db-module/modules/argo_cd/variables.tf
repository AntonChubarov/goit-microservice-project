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

# ---------------- RDS inputs for injecting into the app values ----------------
variable "rds_username" {
  description = "Ім'я користувача для RDS"
  type        = string
}

variable "rds_db_name" {
  description = "Назва бази даних для RDS"
  type        = string
}

variable "rds_password" {
  description = "Пароль для RDS"
  type        = string
  sensitive   = true
}

variable "rds_endpoint" {
  description = "Endpoint для RDS"
  type        = string
}

# ---------------- GitHub repo secret for Argo CD (safe defaults) --------------
# These default to empty so main.tf does not HAVE to pass them to avoid
# templatefile(...) failures. You can still override via TF_VAR_* or tfvars.
variable "github_repo_url" {
  description = "GitHub repository URL used by Argo CD repository Secret"
  type        = string
  default     = ""
}

variable "github_user" {
  description = "GitHub username for the Argo CD repository Secret"
  type        = string
  default     = ""
}

variable "github_pat" {
  description = "GitHub Personal Access Token for the Argo CD repository Secret"
  type        = string
  sensitive   = true
  default     = ""
}
