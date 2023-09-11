output "image_name" {
  description = "The name of the Docker image"
  value       = var.image_name
}

output "repository_url" {
  description = "The URL of the Docker repository"
  value       = aws_ecr_repository.backend_app.repository_url
}

output "backend_repository_arn" {
  description = "The ARN of the Docker repository in ECR"
  value       = aws_ecr_repository.backend_app.arn
}
