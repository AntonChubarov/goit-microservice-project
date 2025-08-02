output "state_bucket_name" {
  value = module.s3_backend.bucket_name
}

output "state_table_name" {
  value = module.s3_backend.dynamodb_table_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "db_endpoint" {
  value = module.rds.endpoint
}

output "db_port" {
  value = module.rds.port
}

output "db_name" {
  value = module.rds.db_name
}

output "db_username" {
  value = module.rds.username
}

output "db_password" {
  value     = module.rds.password
  sensitive = true
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  value = module.eks.oidc_provider_url
}

output "jenkins_url" {
  value = module.jenkins.jenkins_url
}

output "argocd_url" {
  value = module.argo_cd.argocd_url
}
