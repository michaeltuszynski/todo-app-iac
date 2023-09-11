## ALB Cloudwatch Log Group
resource "aws_cloudwatch_log_group" "this" {
  name = "alb-log-group"
}

resource "aws_security_group" "alb_sg" {
  name        = "${var.app_name}-alb-sg"
  vpc_id      = var.vpc_id
  description = "Security group for the ${var.app_name} ALB"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = var.backend_port
    to_port     = var.backend_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0", var.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "this" {
  name                       = "${var.app_name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  enable_deletion_protection = false
  enable_http2               = true
  subnets                    = var.public_subnets

  enable_cross_zone_load_balancing = true

  access_logs {
    bucket = aws_cloudwatch_log_group.this.arn
  }
}

resource "aws_lb_target_group" "default" {
  name        = "${var.app_name}-default-tg"
  port        = var.backend_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "60"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = var.health_check_path
    unhealthy_threshold = "2"
  }
}

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.this.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.ssl_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  depends_on = [aws_lb_target_group.default]
}

resource "aws_lb_listener_rule" "not_found_response" {
  listener_arn = aws_lb_listener.https_listener.arn

  # This condition effectively matches all paths.
  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  # Setting priority to a high value ensures this is the last rule to be evaluated.
  priority = 999
}

resource "aws_lb_listener_rule" "back_end_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  condition {
    path_pattern {
      values = var.application_paths
    }
  }
}

data "aws_acm_certificate" "ssl_cert" {
  domain   = var.custom_domain_name
  statuses = ["ISSUED"]
}

resource "aws_route53_record" "backend_alias_record" {
  zone_id = var.hosted_zone_id
  name    = "backend.${var.custom_domain_name}."
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
