output "image_name" {
  description = "The name of the Docker image"
  value       = var.image_name
}

output "repository_url" {
  description = "The URL of the Docker repository"
  value       = aws_ecr_repository.ts_backend_app.repository_url
}
