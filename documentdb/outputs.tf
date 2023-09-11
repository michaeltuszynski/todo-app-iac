output "secrets_arn" {
  value = aws_secretsmanager_secret.docdb_credentials.arn
}

output "secret_string_arn" {
  value = aws_secretsmanager_secret_version.db_secret_version.arn
}

output "db_cluster_endpoint" {
  value = aws_docdb_cluster_instance.docdb_instance.endpoint
}

