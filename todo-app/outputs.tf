output "load_balancer_ip" {
  value = aws_lb.todo_app_lb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}
