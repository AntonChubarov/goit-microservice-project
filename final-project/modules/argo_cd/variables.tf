variable "name" {
  description = "Назва Helm-релізу"
  type        = string
  default     = "argo-cd"
  nullable    = false
}

variable "namespace" {
  description = "K8s namespace для Argo CD"
  type        = string
  default     = "argocd"
  nullable    = false
}

variable "chart_version" {
  description = "Версія Argo CD чарта"
  type        = string
  default     = "5.46.4"
  nullable    = false
}

# ---------------- RDS inputs for injecting into the app values ----------------
variable "rds_username" {
  description = "Ім'я користувача для RDS"
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.rds_username)) > 0
    error_message = "rds_username must be a non-empty string."
  }
}

variable "rds_db_name" {
  description = "Назва бази даних для RDS"
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.rds_db_name)) > 0
    error_message = "rds_db_name must be a non-empty string."
  }
}

variable "rds_password" {
  description = "Пароль для RDS"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(trimspace(var.rds_password)) > 0
    error_message = "rds_password must be provided (non-empty)."
  }
}

variable "rds_endpoint" {
  description = "Endpoint для RDS (може містити :порт)"
  type        = string
  nullable    = false

  # Basic sanity check: host like 'xxx.rds.amazonaws.com' optionally with ':5432'
  validation {
    condition     = can(regex("^[-a-zA-Z0-9_.]+(\\:[0-9]+)?$", var.rds_endpoint))
    error_message = "rds_endpoint must be a hostname (optionally with :port)."
  }
}

# ---------------- GitHub repo secret for Argo CD (safe defaults) --------------
# Параметри нижче не обов'язкові. Порожні значення допустимі.
variable "github_repo_url" {
  description = "GitHub repository URL used by Argo CD repository Secret"
  type        = string
  default     = ""

  # Allow empty OR something that looks like an HTTPS URL
  validation {
    condition     = var.github_repo_url == "" || can(regex("^https://", var.github_repo_url))
    error_message = "github_repo_url must be empty or start with https://"
  }
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
