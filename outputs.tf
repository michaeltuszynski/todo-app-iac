output "load_balancer_ip" {
  value = aws_lb.todo_app_lb.dns_name
}