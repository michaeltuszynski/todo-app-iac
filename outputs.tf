output "load_balancer_ip" {
  value = module.alb.load_balancer_name
}

output "cloudfront_distribution_id" {
  value = module.frontend.cloudfront_distribution_id
}


