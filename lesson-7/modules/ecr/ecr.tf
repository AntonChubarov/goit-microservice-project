resource "aws_ecr_repository" "this" {
  name                 = var.ecr_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "retain recent images"
      selection    = {
        tagStatus = "any"
        countType = "imageCountMoreThan"
        countNumber = 20 }
      action       = {
        type = "expire"
      }
    }]
  })
}
