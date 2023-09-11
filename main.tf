module "networking" {
  source                        = "./networking"
  vpc_cidr_block                = "10.0.0.0/16"
  vpc_name                      = "${var.app_name}-vpc"
  application_security_group_id = aws_security_group.ecs_tasks.id
  region                        = var.region
  app_name                      = var.app_name
}

module "alb" {
  source             = "./alb"
  app_name           = var.app_name
  backend_port       = var.backend_port
  custom_domain_name = var.custom_domain_name
  hosted_zone_id     = var.hosted_zone_id
  vpc_id             = module.networking.vpc_id
  public_subnets     = module.networking.public_subnets
  cidr_block         = module.networking.cidr_block
  health_check_path  = "/health"
  application_paths  = ["/health", "/todos", "/todos/*"]

}

module "frontend" {
  source             = "./frontend"
  app_name           = var.app_name
  custom_domain_name = var.custom_domain_name
  hosted_zone_id     = var.hosted_zone_id
}

module "cicd" {
  source                     = "./ci-cd"
  app_name                   = var.app_name
  region                     = var.region
  backend_port               = var.backend_port
  db_port                    = var.db_port
  github_backend_repo        = var.github_backend_repo
  github_frontend_repo       = var.github_frontend_repo
  github_owner               = var.github_owner
  github_token               = var.github_token
  custom_domain_name         = var.custom_domain_name
  cloudfront_distribution_id = module.frontend.cloudfront_distribution_id
  frontend_bucket            = module.frontend.frontend_bucket
  cluster_name               = aws_ecs_cluster.todo_app_cluster.name
  service_name               = aws_ecs_service.backend.name
}

module "documentdb" {
  source          = "./documentdb"
  app_name        = var.app_name
  db_port         = var.db_port
  vpc_id          = module.networking.vpc_id
  private_subnets = module.networking.private_subnets
  vpc_cidr_block  = module.networking.cidr_block
}

module "iam" {
  source                 = "./iam"
  app_name               = var.app_name
  region                 = var.region
  secret_arn             = module.documentdb.secrets_arn
  bucket_arn             = module.frontend.frontend_bucket_arn
  backend_repository_arn = module.cicd.backend_repository_arn
}

## ECS Cluster
locals {
  backend_port_number = tonumber(var.backend_port)
  default_route       = "0.0.0.0/0"
}

# ECS Cluster Security Group
resource "aws_security_group" "ecs_cluster" {
  name        = "${var.app_name}-ecs-cluster-sg"
  description = "Security group for ECS cluster instances"
  vpc_id      = module.networking.vpc_id

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
    cidr_blocks = [local.default_route]
  }

  tags = {
    Name = "${var.app_name}-ecs-cluster-sg"
  }
}

# ECS Security Group for Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.app_name}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = module.networking.vpc_id

  # Inbound rules
  ingress {
    from_port   = var.backend_port
    to_port     = var.backend_port
    protocol    = "tcp"
    cidr_blocks = [local.default_route]
  }

  ingress {
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = [local.default_route, module.networking.cidr_block]
  }

  ingress {
    from_port   = var.https_port
    to_port     = var.https_port
    protocol    = "tcp"
    cidr_blocks = [module.networking.cidr_block]
  }

  # Outbound rules (default allows all outbound traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [local.default_route]
  }

  tags = {
    Name = "${var.app_name}-${var.app_environment}-ecs-tasks-sg"
  }
}

## ECS Cloudwatch Log Group
resource "aws_cloudwatch_log_group" "ecs-tasks" {
  name = "${var.app_name}-${var.app_environment}-ecs-tasks-logs"
}

# Define the ECS Cluster
resource "aws_ecs_cluster" "todo_app_cluster" {
  name = "${var.app_name}-${var.app_environment}-cluster"
}

# Backend Task Definition
resource "aws_ecs_task_definition" "backend" {
  family                   = "backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = module.iam.ecs_execution_role
  task_role_arn            = module.iam.ecs_task_role

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${module.cicd.repository_url}:latest"
      essential = true
      portMappings = [{
        containerPort = local.backend_port_number
      }]

      secrets = [{
        name      = "DB_USER",
        valueFrom = "${module.documentdb.secret_string_arn}:username::"
        }, {
        name      = "DB_PASSWORD",
        valueFrom = "${module.documentdb.secret_string_arn}:password::"
      }]

      environment = [
        {
          name  = "DB_ENDPOINT",
          value = module.documentdb.db_cluster_endpoint
        },
        {
          name  = "DB_PORT",
          value = var.db_port
        },
        {
          name  = "NODEPORT",
          value = var.backend_port
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs-tasks.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "backend"
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
    subnets         = module.networking.private_subnets
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    target_group_arn = module.alb.target_group_arn
    container_name   = "backend"
    container_port   = var.backend_port
  }

  deployment_maximum_percent         = var.max_percentage
  deployment_minimum_healthy_percent = var.min_percentage

  lifecycle {
    ignore_changes = [desired_count] //used to avoid Terraform to reset the desired_count if auto-scaling changes it.
  }

  depends_on = [module.alb, module.documentdb]
}

# Autoscaling Targets
resource "aws_appautoscaling_target" "ecs_backend_target" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.todo_app_cluster.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Autoscaling Policies
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
