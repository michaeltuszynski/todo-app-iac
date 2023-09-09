
## ECR Repositories
data "aws_ecr_repository" "ts_backend_repo" {
  name = "ts_backend_app"
}

## Cloudwatch Log Group
resource "aws_cloudwatch_log_group" "ecs-tasks" {
  name = "${var.app_name}-${var.app_environment}-ecs-tasks-logs"

  # tags = {
  #   Application = var.app_name
  #   Environment = var.app_environment
  # }
}

## Network Configuration
data "aws_availability_zones" "available_zones" {
  state = "available"
}

resource "aws_vpc" "todo_vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  # tags = {
  #   Name        = "${var.app_name}-vpc"
  #   Environment = var.app_environment
  # }
}

resource "aws_subnet" "public" {
  count                   = 2
  cidr_block              = cidrsubnet(aws_vpc.todo_vpc.cidr_block, 8, 2 + count.index)
  availability_zone       = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id                  = aws_vpc.todo_vpc.id
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  cidr_block        = cidrsubnet(aws_vpc.todo_vpc.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id            = aws_vpc.todo_vpc.id

  tags = {
    Name = "private-subnet-${count.index}"
  }
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.todo_vpc.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.todo_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  vpc        = true
  depends_on = [aws_internet_gateway.gateway]
}

resource "aws_nat_gateway" "nat_gateway" {
  subnet_id     = aws_subnet.public[0].id
  allocation_id = aws_eip.nat.id
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.todo_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

## VPC Endpoints

# VPC Endpoint for Amazon S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.todo_vpc.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private.*.id
}

# VPC Endpoint for ECR (Docker)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id             = aws_vpc.todo_vpc.id
  service_name       = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.ecs_tasks.id]
  subnet_ids         = aws_subnet.private.*.id
}

# VPC Endpoint for ECR (API)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id             = aws_vpc.todo_vpc.id
  service_name       = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.ecs_tasks.id]
  subnet_ids         = aws_subnet.private.*.id
}

# VPC Endpoint for CloudWatch Logs
resource "aws_vpc_endpoint" "logs" {
  vpc_id             = aws_vpc.todo_vpc.id
  service_name       = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.ecs_tasks.id]
  subnet_ids         = aws_subnet.private.*.id
}

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  vpc_id      = aws_vpc.todo_vpc.id
  description = "Security group for the ALB"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
    cidr_blocks = ["0.0.0.0/0", aws_vpc.todo_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "todo_app_alb" {
  name                       = "${var.app_name}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  enable_deletion_protection = false
  enable_http2               = true
  subnets                    = aws_subnet.public.*.id

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "default" {
  name        = "default-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.todo_vpc.id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "60"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/health"
    unhealthy_threshold = "2"
  }
}

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.todo_app_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.ssl_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
}

resource "aws_lb_listener_rule" "back_end_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  condition {
    path_pattern {
      values = ["/health", "/todos"]
    }
  }
}



resource "aws_route53_record" "alias_record" {
  zone_id = var.hosted_zone_id
  name    = "backend.mptdemo.com."
  type    = "A"

  alias {
    name                   = aws_lb.todo_app_alb.dns_name
    zone_id                = aws_lb.todo_app_alb.zone_id
    evaluate_target_health = true
  }
}

# ## ALB Configuration
# resource "aws_security_group" "lb" {
#   name   = "todo-alb-security-group"
#   vpc_id = aws_vpc.todo_vpc.id

#   ingress {
#     protocol    = "tcp"
#     from_port   = 443
#     to_port     = 5000
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# resource "aws_lb" "todo_app_lb" {
#   name            = "todo-app-lb"
#   subnets         = aws_subnet.public.*.id
#   security_groups = [aws_security_group.lb.id]
# }

# resource "aws_lb_target_group" "todo_app_backend_target_group" {
#   name        = "${var.app_name}-backend-target-group"
#   port        = 5000
#   protocol    = "HTTP"
#   vpc_id      = aws_vpc.todo_vpc.id
#   target_type = "ip"

#   health_check {
#     healthy_threshold   = "3"
#     interval            = "60"
#     protocol            = "HTTP"
#     matcher             = "200"
#     timeout             = "3"
#     path                = "/health"
#     unhealthy_threshold = "2"
#   }

#   tags = {
#     Name        = "${var.app_name}-lb-tg"
#     Environment = var.app_environment
#   }
# }

data "aws_acm_certificate" "ssl_cert" {
  domain   = "mptdemo.com"
  statuses = ["ISSUED"]
}

data "aws_acm_certificate" "cf_distro" {
  domain      = "www.mptdemo.com"
  most_recent = true

  provider = aws.east
}

# resource "aws_lb_listener" "todo_app_alb_listener" {
#   load_balancer_arn = aws_lb.todo_app_lb.id
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-2016-08"
#   certificate_arn   = data.aws_acm_certificate.ssl_cert.arn

#   default_action {
#     type = "fixed-response"
#     fixed_response {
#       content_type = "text/plain"
#       message_body = "404: Not Found"
#       status_code  = "404"
#     }
#   }
# }

# resource "aws_lb_listener_rule" "back_end_rule" {
#   listener_arn = aws_lb_listener.todo_app_alb_listener.arn
#   priority     = 200

#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.todo_app_backend_target_group.arn
#   }

#   condition {
#     path_pattern {
#       values = ["/health", "/todos"]
#     }
#   }
# }

## Create an S3 Bucket
resource "random_pet" "bucket_name" {
  length = 2
}

resource "aws_s3_bucket" "todo_app_website" {
  bucket        = "${var.app_name}-bucket-${random_pet.bucket_name.id}"
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "frontend_website" {
  bucket = aws_s3_bucket.todo_app_website.bucket
  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.todo_app_website.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.todo_app_website.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront Distribution"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.todo_app_website.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  aliases = ["www.mptdemo.com"]

  viewer_certificate {
    # cloudfront_default_certificate = true
    acm_certificate_arn      = data.aws_acm_certificate.cf_distro.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
}

resource "aws_route53_record" "cloudfront_alias_record" {
  zone_id = var.hosted_zone_id
  name    = "www.mptdemo.com."
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for website bucket"
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.todo_app_website.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "CloudFrontOAI",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${aws_cloudfront_origin_access_identity.oai.id}"
        },
        Action   = "s3:GetObject",
        Resource = "arn:aws:s3:::${aws_s3_bucket.todo_app_website.bucket}/*"
      }
    ]
  })
}

## IAM Roles and Policies
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role" "s3_role" {
  name = "S3FullAccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ecs.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_role" "docdb_cloudwatch_role" {
  name = "DocDBCloudWatchRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "custom_ecr_permissions" {
  name        = "ECRTaskCustomPermissions"
  description = "Custom permissions for ECR tasks"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ],
        Effect   = "Allow",
        Resource = ["*"],
        Sid      = "AllowPushPull"
      }
    ]
  })
}

resource "aws_iam_policy" "custom_cloudwatch_permissions" {
  name        = "CloudWatchCustomPermissions"
  description = "Custom permissions for Cloudwatch"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Effect   = "Allow",
        Resource = ["arn:aws:logs:*:*:*"],
        Sid      = "AllowCloudWatchLogs"
      }
    ]
  })
}

resource "aws_iam_policy" "s3_policy_permissions" {
  name        = "S3FullAccessPolicy"
  description = "Policy that allows full access to a specific S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Effect = "Allow",
        Resource = [
          aws_s3_bucket.todo_app_website.arn,
          "${aws_s3_bucket.todo_app_website.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "ecs_secrets_access" {
  name        = "ECSAccessToSecrets"
  description = "Allow ECS tasks to retrieve secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "secretsmanager:GetSecretValue"
      ],
      Resource = aws_secretsmanager_secret.docdb_credentials.arn,
      Effect   = "Allow"
    }]
  })
}

resource "aws_iam_policy" "ecs_docdb_access" {
  name        = "ecs_docdb_access"
  description = "Permissions for ECS to access DocumentDB and related EC2 resources."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "DocDBFull",
        Effect = "Allow",
        Action = [
          "docdb:*"
        ],
        Resource = "*"
      },
      {
        Sid    = "EC2Networking",
        Effect = "Allow",
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "custom_ecr_policy_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.custom_ecr_permissions.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.custom_cloudwatch_permissions.arn
}

resource "aws_iam_role_policy_attachment" "custom_s3_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.s3_policy_permissions.arn
}

resource "aws_iam_role_policy_attachment" "s3_role_policy_attachment" {
  role       = aws_iam_role.s3_role.name
  policy_arn = aws_iam_policy.s3_policy_permissions.arn
}

resource "aws_iam_role_policy_attachment" "ecs_secrets_access_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_secrets_access.arn
}

resource "aws_iam_role_policy_attachment" "ecs_secrets_access_exec_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecs_secrets_access.arn
}


resource "aws_iam_role_policy_attachment" "ecs_docdb_attach" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_docdb_access.arn
}

resource "aws_iam_role_policy_attachment" "docdb_cloudwatch_attach" {
  role       = aws_iam_role.docdb_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

## Security Groups

# ECS Security Group for Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "ecs_tasks_sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.todo_vpc.id

  # Inbound rules
  ingress {
    from_port   = 5000 # for HTTP
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 27017 # for HTTP
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0", aws_vpc.todo_vpc.cidr_block]
  }

  ingress {
    from_port   = 3000 # for HTTP
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0", aws_vpc.todo_vpc.cidr_block]
  }

  ingress {
    from_port   = 5000 # for HTTP
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rules (default allows all outbound traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs_tasks_sg"
  }
}

resource "aws_security_group" "docdb_sg" {
  name        = "docdb_sg"
  description = "Security group for DocumentDB"
  vpc_id      = aws_vpc.todo_vpc.id

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0", aws_vpc.todo_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "docdb_sg"
  }
}

# ECS Cluster Security Group
resource "aws_security_group" "ecs_cluster" {
  name        = "ecs_cluster_sg"
  description = "Security group for ECS cluster instances"
  vpc_id      = aws_vpc.todo_vpc.id

  # Allow inbound traffic from ECS tasks
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "udp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  # Outbound rules (default allows all outbound traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs_cluster_sg"
  }
}

resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "random_pet" "secret_name" {
  length = 2
}

resource "aws_secretsmanager_secret" "docdb_credentials" {
  name = "${var.app_name}-docdb_credentials-${random_pet.secret_name.id}"
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id     = aws_secretsmanager_secret.docdb_credentials.id
  secret_string = "{\"username\":\"root\", \"password\":\"${random_password.db_password.result}\"}"
}

## DocumentDB (Mongo on AWS)
resource "aws_docdb_cluster" "todo_app_docdb_cluster" {
  cluster_identifier              = "todo-app-docdb-cluster"
  skip_final_snapshot             = true
  engine_version                  = "4.0.0"
  backup_retention_period         = 1
  enabled_cloudwatch_logs_exports = ["audit", "profiler"]
  master_username                 = jsondecode(aws_secretsmanager_secret_version.db_secret_version.secret_string)["username"]
  master_password                 = jsondecode(aws_secretsmanager_secret_version.db_secret_version.secret_string)["password"]
  db_subnet_group_name            = aws_docdb_subnet_group.default.name
  vpc_security_group_ids          = [aws_security_group.docdb_sg.id]
}

resource "aws_docdb_cluster_instance" "docdb_instance" {
  identifier         = "docdb-instance"
  cluster_identifier = aws_docdb_cluster.todo_app_docdb_cluster.cluster_identifier
  instance_class     = "db.r5.large"
}

resource "aws_docdb_subnet_group" "default" {
  name       = "main"
  subnet_ids = aws_subnet.private.*.id

  tags = {
    Name = "default"
  }
}

## ECS

# Define the ECS Cluster
resource "aws_ecs_cluster" "todo_app_cluster" {
  name = "${var.app_name}-cluster"
}

# Backend Task Definition
resource "aws_ecs_task_definition" "backend" {
  family                   = "backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${data.aws_ecr_repository.ts_backend_repo.repository_url}:latest"
      essential = true
      portMappings = [{
        containerPort = 5000
      }]


      secrets = [{
        name      = "DB_USER",
        valueFrom = "${aws_secretsmanager_secret_version.db_secret_version.arn}:username::"
        }, {
        name      = "DB_PASSWORD",
        valueFrom = "${aws_secretsmanager_secret_version.db_secret_version.arn}:password::"
      }]

      environment = [
        {
          name  = "DB_ENDPOINT",
          value = aws_docdb_cluster_instance.docdb_instance.endpoint
        },
        {
          name  = "NODEPORT",
          value = "5000"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs-tasks.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ts-backend"
        }
      }
    }
  ])
}

# Backend ECS Service
resource "aws_ecs_service" "backend" {
  name            = "backend-service"
  cluster         = aws_ecs_cluster.todo_app_cluster.id
  task_definition = aws_ecs_task_definition.backend.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  network_configuration {
    subnets         = aws_subnet.private.*.id
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    #target_group_arn = aws_lb_target_group.todo_app_backend_target_group.arn
    target_group_arn = aws_lb_target_group.default.arn
    container_name   = "backend"
    container_port   = 5000
  }

  deployment_maximum_percent         = var.max_percentage
  deployment_minimum_healthy_percent = var.min_percentage

  lifecycle {
    ignore_changes = [desired_count] //used to avoid Terraform to reset the desired_count if auto-scaling changes it.
  }

  #depends_on = [aws_lb.todo_app_lb, aws_docdb_cluster.todo_app_docdb_cluster]
  depends_on = [aws_lb.todo_app_alb, aws_docdb_cluster.todo_app_docdb_cluster]
}



# Autoscaling Targets
resource "aws_appautoscaling_target" "ecs_backend_target" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.todo_app_cluster.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}



# ## Autoscaling Policies
resource "aws_appautoscaling_policy" "backend_scale_out" {
  name               = "${var.app_name}-ecs-backend-scale-out"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.ecs_backend_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_backend_target.scalable_dimension

  policy_type = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = var.target_value_scale_out
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "backend_scale_in" {
  name               = "${var.app_name}-ecs-backend-scale-in"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.ecs_backend_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_backend_target.scalable_dimension

  policy_type = "StepScaling"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 300
    metric_aggregation_type = "Average"

    step_adjustment {
      scaling_adjustment          = 1
      metric_interval_lower_bound = 30
      metric_interval_upper_bound = 50
    }

    step_adjustment {
      scaling_adjustment          = 2
      metric_interval_lower_bound = 50
    }

  }
}
