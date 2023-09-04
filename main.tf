
## ECR Repositories
data "aws_ecr_repository" "ts_backend_repo" {
  name = "ts_backend_app"
}

# data "aws_ecr_repository" "ts_frontend_repo" {
#   name = "ts_frontend_app"
# }

data "aws_ecr_repository" "ts_database_repo" {
  name = "mongo"
}

## Cloudwatch Log Group
resource "aws_cloudwatch_log_group" "ecs-tasks" {
  name = "${var.app_name}-${var.app_environment}-ecs-tasks-logs"

  tags = {
    Application = var.app_name
    Environment = var.app_environment
  }
}

## Network Configuration
data "aws_availability_zones" "available_zones" {
  state = "available"
}

resource "aws_vpc" "todo_vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "${var.app_name}-vpc"
    Environment = var.app_environment
  }
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

# resource "aws_route" "internet_access" {
#   route_table_id         = aws_vpc.todo_vpc.main_route_table_id
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = aws_internet_gateway.gateway.id
# }

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

# VPC Endpoint for Parameter Store (SSM)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id             = aws_vpc.todo_vpc.id
  service_name       = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.ecs_tasks.id]
  subnet_ids         = aws_subnet.private.*.id
}


## ALB Configuration
resource "aws_security_group" "lb" {
  name   = "todo-alb-security-group"
  vpc_id = aws_vpc.todo_vpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 5000
    to_port     = 5000
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "todo_app_lb" {
  name            = "todo-app-lb"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.lb.id]
}

# resource "aws_lb_target_group" "todo_app_frontend_target_group" {
#   name        = "${var.app_name}-frontend-target-group"
#   port        = 80
#   protocol    = "HTTP"
#   vpc_id      = aws_vpc.todo_vpc.id
#   target_type = "ip"

#   health_check {
#     healthy_threshold   = "3"
#     interval            = "300"
#     protocol            = "HTTP"
#     matcher             = "200"
#     timeout             = "3"
#     path                = "/health.html"
#     unhealthy_threshold = "2"
#   }

#   tags = {
#     Name        = "${var.app_name}-lb-tg"
#     Environment = var.app_environment
#   }
# }

resource "aws_lb_target_group" "todo_app_backend_target_group" {
  name        = "${var.app_name}-backend-target-group"
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

  tags = {
    Name        = "${var.app_name}-lb-tg"
    Environment = var.app_environment
  }
}

resource "aws_lb_listener" "todo_app_alb_listener" {
  load_balancer_arn = aws_lb.todo_app_lb.id
  port              = 5000
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: Not Found"
      status_code  = "404"
    }
  }
}

# resource "aws_lb_listener_rule" "front_end_rule" {
#   listener_arn = aws_lb_listener.todo_app_alb_listener.arn
#   priority     = 100

#   action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.todo_app_frontend_target_group.arn
#   }

#   condition {
#     path_pattern {
#       values = ["/*"]
#     }
#   }
# }

resource "aws_lb_listener_rule" "back_end_rule" {
  listener_arn = aws_lb_listener.todo_app_alb_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.todo_app_backend_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/health", "/todos"]
    }
  }
}



## Database Params - move to Secrets Manager
data "aws_ssm_parameter" "db_username" {
  name = "/database/username"
}

data "aws_ssm_parameter" "db_password" {
  name = "/database/password"
}

## Create an S3 Bucket
resource "random_pet" "bucket_name" {
  length = 2
}

resource "aws_s3_bucket" "todo_app_bucket" {
  bucket = "${var.app_name}-bucket-${random_pet.bucket_name.id}"
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

resource "aws_iam_policy" "custom_ssm_permissions" {
  name        = "ECSTaskCustomPermissions"
  description = "Custom permissions for ECS tasks"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = ["ssm:GetParameters"],
        Effect = "Allow",
        Resource = ["arn:aws:ssm:region:account-id:parameter/database/username",
        "arn:aws:ssm:region:account-id:parameter/database/password"]
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

resource "aws_iam_policy" "custom_service_disovery_permissions" {
  name        = "ServiceDiscoveryCustomPermissions"
  description = "Custom permissions for Service Discovery"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "servicediscovery:DiscoverInstances",
          "servicediscovery:GetInstancesHealthStatus",
          "servicediscovery:GetOperation",
          "servicediscovery:GetService",
          "servicediscovery:ListInstances",
          "servicediscovery:ListNamespaces",
          "servicediscovery:ListOperations",
          "servicediscovery:ListServices",
          "servicediscovery:RegisterInstance",
          "servicediscovery:DeregisterInstance"
        ],
        Effect   = "Allow",
        Resource = ["*"],
        Sid      = "AllowServiceDiscovery"
      }
    ]
  })
}

resource "aws_iam_policy" "custom_route53_permissions" {
  name        = "Route53CustomPermissions"
  description = "Custom permissions for Route53"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "route53:CreateHealthCheck",
          "route53:GetHealthCheck",
          "route53:UpdateHealthCheck",
          "route53:DeleteHealthCheck",
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
          "route53:CreateHostedZone",
          "route53:DeleteHostedZone",
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ],
        Effect   = "Allow",
        Resource = ["*"],
        Sid      = "AllowRoute53"
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
          aws_s3_bucket.todo_app_bucket.arn,
          "${aws_s3_bucket.todo_app_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "custom_service_discovery_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.custom_service_disovery_permissions.arn
}

resource "aws_iam_role_policy_attachment" "custom_route53_policy_attachment_task_role" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.custom_route53_permissions.arn
}

resource "aws_iam_role_policy_attachment" "custom_route53_policy_attachment_exec_role" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.custom_route53_permissions.arn
}

resource "aws_iam_role_policy_attachment" "custom_ssm_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.custom_ssm_permissions.arn
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

## Service discovery
resource "aws_service_discovery_private_dns_namespace" "namespace" {
  name = "local"
  vpc  = aws_vpc.todo_vpc.id
}

# resource "aws_service_discovery_service" "todo_frontend_service" {
#   name = "${var.app_name}-frontend-service"
#   dns_config {
#     namespace_id = aws_service_discovery_private_dns_namespace.namespace.id
#     dns_records {
#       ttl  = 10
#       type = "A"
#     }
#     routing_policy = "MULTIVALUE"
#   }

#   health_check_custom_config {
#     failure_threshold = 10
#   }
# }

resource "aws_service_discovery_service" "todo_backend_service" {
  name = "${var.app_name}-backend-service"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.namespace.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 10
  }
}

resource "aws_service_discovery_service" "todo_database_service" {
  name = "${var.app_name}-database-service"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.namespace.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 10
  }
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
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80 # for HTTP
    to_port     = 80
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

## ECS

# Define the ECS Cluster
resource "aws_ecs_cluster" "todo_app_cluster" {
  name = "${var.app_name}-cluster"
}

# Frontend Task Definition
# resource "aws_ecs_task_definition" "frontend" {
#   family                   = "frontend"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = "256"
#   memory                   = "512"
#   execution_role_arn       = aws_iam_role.ecs_execution_role.arn
#   task_role_arn            = aws_iam_role.ecs_task_role.arn

#   container_definitions = jsonencode([
#     {
#       name      = "frontend"
#       image     = "${data.aws_ecr_repository.ts_frontend_repo.repository_url}:latest"
#       essential = true
#       portMappings = [{
#         containerPort = 80
#       }]

#       environment = [
#         {
#           name  = "REACT_APP_BACKEND_URI",
#           value = "${aws_service_discovery_service.todo_backend_service.name}.${aws_service_discovery_private_dns_namespace.namespace.name}:5000"
#         },
#         {
#           name  = "REACT_APP_NODEPORT",
#           value = "5000"
#         }
#       ]

#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           "awslogs-group"         = aws_cloudwatch_log_group.ecs-tasks.name
#           "awslogs-region"        = var.region
#           "awslogs-stream-prefix" = "ts-frontend"
#         }
#       },
#     }
#   ])
# }

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

      environment = [
        {
          name  = "MONGODB_URI",
          value = "mongodb://${data.aws_ssm_parameter.db_username.value}:${data.aws_ssm_parameter.db_password.value}@${aws_service_discovery_service.todo_database_service.name}.${aws_service_discovery_private_dns_namespace.namespace.name}:27017/?authSource=admin&readPreference=primary&ssl=false&directConnection=true"
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

# Database Task Definition
resource "aws_ecs_task_definition" "database" {
  family                   = "database"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "database"
      image = "${data.aws_ecr_repository.ts_database_repo.repository_url}:latest"
      portMappings = [{
        containerPort = 27017
      }]

      environment = [
        {
          name  = "MONGO_INITDB_ROOT_USERNAME",
          value = "${data.aws_ssm_parameter.db_username.value}"
        },
        {
          name  = "MONGO_INITDB_ROOT_PASSWORD",
          value = "${data.aws_ssm_parameter.db_password.value}"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs-tasks.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ts-database"
        }
      }
    }
  ])
}

# Frontend ECS Service
# resource "aws_ecs_service" "frontend" {
#   name            = "frontend-service"
#   cluster         = aws_ecs_cluster.todo_app_cluster.id
#   task_definition = aws_ecs_task_definition.frontend.arn
#   launch_type     = "FARGATE"
#   desired_count   = var.desired_count

#   network_configuration {
#     subnets         = aws_subnet.private.*.id
#     security_groups = [aws_security_group.ecs_tasks.id]
#   }

#   load_balancer {
#     target_group_arn = aws_lb_target_group.todo_app_frontend_target_group.arn
#     container_name   = "frontend"
#     container_port   = 80
#   }

#   deployment_maximum_percent         = var.max_percentage
#   deployment_minimum_healthy_percent = var.min_percentage

#   lifecycle {
#     ignore_changes = [desired_count] //used to avoid Terraform to reset the desired_count if auto-scaling changes it.
#   }

#   service_registries {
#     registry_arn = aws_service_discovery_service.todo_frontend_service.arn
#   }

#   depends_on = [aws_lb.todo_app_lb, aws_ecs_service.backend, aws_ecs_service.database]
# }

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
    target_group_arn = aws_lb_target_group.todo_app_backend_target_group.arn
    container_name   = "backend"
    container_port   = 5000
  }

  deployment_maximum_percent         = var.max_percentage
  deployment_minimum_healthy_percent = var.min_percentage

  lifecycle {
    ignore_changes = [desired_count] //used to avoid Terraform to reset the desired_count if auto-scaling changes it.
  }

  service_registries {
    registry_arn = aws_service_discovery_service.todo_backend_service.arn
  }

  depends_on = [aws_lb.todo_app_lb, aws_ecs_service.database]
}

# Database ECS Service
resource "aws_ecs_service" "database" {
  name            = "database-service"
  cluster         = aws_ecs_cluster.todo_app_cluster.id
  task_definition = aws_ecs_task_definition.database.arn
  launch_type     = "FARGATE"
  desired_count   = var.desired_count

  network_configuration {
    subnets         = aws_subnet.private.*.id
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  deployment_maximum_percent         = var.max_percentage
  deployment_minimum_healthy_percent = var.min_percentage

  lifecycle {
    ignore_changes = [desired_count] //used to avoid Terraform to reset the desired_count if auto-scaling changes it.
  }

  service_registries {
    registry_arn = aws_service_discovery_service.todo_database_service.arn
  }

}

# Autoscaling Targets
# resource "aws_appautoscaling_target" "ecs_frontend_target" {
#   max_capacity       = var.max_capacity
#   min_capacity       = var.min_capacity
#   resource_id        = "service/${aws_ecs_cluster.todo_app_cluster.name}/${aws_ecs_service.frontend.name}"
#   scalable_dimension = "ecs:service:DesiredCount"
#   service_namespace  = "ecs"
# }

resource "aws_appautoscaling_target" "ecs_backend_target" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.todo_app_cluster.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_target" "ecs_database_target" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.todo_app_cluster.name}/${aws_ecs_service.database.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# ## Autoscaling Policies
# resource "aws_appautoscaling_policy" "frontend_scale_out" {
#   name               = "${var.app_name}-ecs-frontend-scale-out"
#   service_namespace  = "ecs"
#   resource_id        = aws_appautoscaling_target.ecs_frontend_target.resource_id
#   scalable_dimension = aws_appautoscaling_target.ecs_frontend_target.scalable_dimension

#   policy_type = "TargetTrackingScaling"

#   target_tracking_scaling_policy_configuration {
#     target_value       = var.target_value_scale_out
#     scale_in_cooldown  = var.scale_in_cooldown
#     scale_out_cooldown = var.scale_out_cooldown

#     predefined_metric_specification {
#       predefined_metric_type = "ECSServiceAverageCPUUtilization"
#     }
#   }
# }

# resource "aws_appautoscaling_policy" "frontend_scale_in" {
#   name               = "${var.app_name}-ecs-frontend-scale-in"
#   service_namespace  = "ecs"
#   resource_id        = aws_appautoscaling_target.ecs_frontend_target.resource_id
#   scalable_dimension = aws_appautoscaling_target.ecs_frontend_target.scalable_dimension

#   policy_type = "StepScaling"

#   step_scaling_policy_configuration {
#     adjustment_type         = "ChangeInCapacity"
#     cooldown                = 300
#     metric_aggregation_type = "Average"

#     step_adjustment {
#       scaling_adjustment          = 1
#       metric_interval_lower_bound = 30
#       metric_interval_upper_bound = 50
#     }

#     step_adjustment {
#       scaling_adjustment          = 2
#       metric_interval_lower_bound = 50
#     }
#   }
# }

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

resource "aws_appautoscaling_policy" "database_scale_out" {
  name               = "${var.app_name}-ecs-database-scale-out"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.ecs_database_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_database_target.scalable_dimension

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

resource "aws_appautoscaling_policy" "database_scale_in" {
  name               = "${var.app_name}-ecs-database-scale-in"
  service_namespace  = "ecs"
  resource_id        = aws_appautoscaling_target.ecs_database_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_database_target.scalable_dimension

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
