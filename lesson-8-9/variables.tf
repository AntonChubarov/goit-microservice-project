variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-cluster-lesson-8-9"
}

variable "vpc_name" {
  default = "vpc-lesson-8-9"
}

variable "instance_type" {
  description = "EC2 instance type for the worker nodes"
  type        = string
  default     = "t2.medium"
}

variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "ecr-repo-lesson-8-9"
}

// github credentials

variable "github_pat" {
  description = "GitHub Personal Access Token"
  type        = string
}

variable "github_user" {
  description = "GitHub username"
  type        = string
}

variable "github_repo_url" {
  description = "GitHub repository name"
  type        = string
}
