provider "aws" {
  region = var.aws_region
}

module "s3_backend" {
  source      = "./modules/s3-backend"
  bucket_name = "lesson-8-9-state"
  table_name  = "terraform-locks"
}

module "vpc" {
  source             = "./modules/vpc"
  vpc_cidr_block     = "10.0.0.0/16"
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets    = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  vpc_name           = "lesson-8-9-vpc"
}

module "ecr" {
  source       = "./modules/ecr"
  ecr_name     = "lesson-8-9-ecr"
  scan_on_push = true
}

module "eks" {
  source                 = "./modules/eks"
  cluster_name           = "lesson-8-9-eks"
  kubernetes_version     = "1.29"
  subnet_ids             = module.vpc.public_subnet_ids
}

module "rds" {
  source              = "./modules/rds"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  vpc_cidr_block      = "10.0.0.0/16"

  db_identifier       = "lesson-8-9-db"
  db_name             = "mydb"
  db_username         = "myuser"

  # optional overrides
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
}
