resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&()*+,-.:;<=>?[]^_{|}~"
}

output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}
