variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "instance_types" {
  description = "EC2 instance types for the managed node-group. Default t3.medium provides 4 GiB RAM and ≈17 pod-IPs."
  type        = list(string)
  default     = ["t3.medium"]
}
