output "load_balancer_ip" {
  value = aws_lb.todo_app_lb.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.todo_app_bucket.id
}