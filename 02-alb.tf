# Define an Application Load Balancer
resource "aws_lb" "this" {
  name                       = "my-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  enable_deletion_protection = false
  enable_http2               = true
  subnets                    = aws_subnet.public.*.id

  enable_cross_zone_load_balancing = true

  depends_on = [aws_security_group.alb_sg, aws_subnet.public]
}

#Define a Security Group that allows ingress on port 443 for HTTPS
resource "aws_security_group" "alb_sg" {
  name        = "my-alb-sg"
  vpc_id      = aws_vpc.this.id
  description = "Security group for the ALB"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  domain_name    = "mptdemo.com"
  hosted_zone_id = "Z0439624142VIWL59PRLZ"
}

# Define a TLS Certificate so the site can run HTTPS.
resource "aws_acm_certificate" "cert" {
  domain_name       = local.domain_name
  validation_method = "DNS"

  #Create a record for the apex record and wildcard subdomains for flexibility
  subject_alternative_names = [
    "${local.domain_name}", "*.${local.domain_name}", "www.${local.domain_name}"
  ]

  tags = {
    Name = "my-domain-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_acm_certificate.cert.domain_validation_options : record.resource_record_name]
}

#Define a listener for HTTPS
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.this.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  depends_on = [aws_lb_target_group.default, aws_acm_certificate.cert]
}

# Define a target group that
resource "aws_lb_target_group" "default" {
  name        = "my-default-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "60"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/health" #the demo API in use for this example has a healthcheck on this path
    unhealthy_threshold = "3"
  }
}

# Define a listener rule that is bespoke for the demo API in this example.
resource "aws_lb_listener_rule" "back_end_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  condition {
    path_pattern {
      values = ["/todos", "/health"]
    }
  }
}

# Define an ALIAS record (A) for the URL to the backend API
resource "aws_route53_record" "backend_alias_record" {
  zone_id = local.hosted_zone_id
  name    = "backend.${local.domain_name}."
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
