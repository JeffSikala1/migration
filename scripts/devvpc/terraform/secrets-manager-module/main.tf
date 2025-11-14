resource "aws_secretsmanager_secret" "db-credentials" {
  name        = var.secret_name
  description = var.description

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db-credentials_version" {
  secret_id     = aws_secretsmanager_secret.db-credentials.id
  secret_string = jsonencode({
    username = var.username
    password = var.password
  })
}
