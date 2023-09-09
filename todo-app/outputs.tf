output "load_balancer_ip" {
  value = aws_lb.todo_app_alb.dns_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.s3_distribution.id
}

output "s3_bucket_id" {
  value = aws_s3_bucket.todo_app_website.id
}
