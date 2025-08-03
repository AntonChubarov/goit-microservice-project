resource "aws_db_subnet_group" "this" {
  name       = "${var.db_identifier}-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.db_identifier}-sg"
  description = "Allow Postgres from EKS nodes (simplified: VPC CIDR)"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "random_password" "db" {
  length           = 20
  special          = true
}

resource "aws_db_instance" "this" {
  identifier                 = var.db_identifier
  engine                     = "postgres"
  instance_class             = var.instance_class
  username                   = var.db_username
  password                   = random_password.db_password.result
  db_name                    = var.db_name

  allocated_storage          = var.allocated_storage
  max_allocated_storage      = 100
  storage_type               = "gp3"
  storage_encrypted          = true

  db_subnet_group_name       = aws_db_subnet_group.this.name
  vpc_security_group_ids     = [aws_security_group.db.id]
  publicly_accessible        = false
  multi_az                   = false

  backup_retention_period    = 0
  deletion_protection        = false
  skip_final_snapshot        = true
  apply_immediately          = true
}
