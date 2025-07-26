terraform {
  backend "s3" {
    bucket         = "lesson-5-state"
    key            = "lesson-5/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}
