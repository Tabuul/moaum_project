resource "random_password" "hmac" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "hmac" {
  name = "${local.name}/MOAUM_AUTH_HMAC_SECRET"
}

resource "aws_secretsmanager_secret_version" "hmac" {
  secret_id     = aws_secretsmanager_secret.hmac.id
  secret_string = random_password.hmac.result
}

resource "aws_secretsmanager_secret" "app" {
  for_each = toset(var.app_secret_names)
  name     = "${local.name}/${each.key}"
}

# Created with a placeholder so the task can start; set the real value afterwards.
resource "aws_secretsmanager_secret_version" "app" {
  for_each      = aws_secretsmanager_secret.app
  secret_id     = each.value.id
  secret_string = "unset"
  lifecycle { ignore_changes = [secret_string] }
}
