data "aws_ecr_repository" "ts_backend_repo" {
  name = "ts_backend_app"
}

data "aws_ecr_repository" "ts_frontend_repo" {
  name = "ts_frontend_app"
}

data "aws_ecr_repository" "ts_database_repo" {
  name = "mongo"
}


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
}

resource "aws_subnet" "private" {
  count             = 2
  cidr_block        = cidrsubnet(aws_vpc.todo_vpc.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id            = aws_vpc.todo_vpc.id
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.todo_vpc.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.todo_vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gateway.id
}

resource "aws_eip" "gateway" {
  count      = 2
  vpc        = true
  depends_on = [aws_internet_gateway.gateway]
}

resource "aws_nat_gateway" "gateway" {
  count         = 2
  subnet_id     = element(aws_subnet.public.*.id, count.index)
  allocation_id = element(aws_eip.gateway.*.id, count.index)
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.todo_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.gateway.*.id, count.index)
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_security_group" "lb" {
  name   = "todo-alb-security-group"
  vpc_id = aws_vpc.todo_vpc.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
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

resource "aws_lb_target_group" "todo_app_target_group" {
  name        = "todo-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.todo_vpc.id
  target_type = "ip"
}

resource "aws_lb_listener" "todo_app_alb_listener" {
  load_balancer_arn = aws_lb.todo_app_lb.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.todo_app_target_group.id
    type             = "forward"
  }
}

data "aws_ssm_parameter" "db_username" {
  name = "/database/username"
}

data "aws_ssm_parameter" "db_password" {
  name = "/database/password"
}

resource "aws_iam_role" "ecs_task_execution_role" {
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

resource "aws_iam_policy" "custom_ecs_permissions" {
  name        = "MyECSTaskCustomPermissions"
  description = "My custom permissions for ECS tasks"

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

resource "aws_iam_role_policy_attachment" "custom_ecs_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.custom_ecs_permissions.arn
}

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

# ECS Cluster
resource "aws_ecs_cluster" "my_cluster" {
  name = "my-cluster"
}

# Backend Task Definition
resource "aws_ecs_task_definition" "backend" {
  family                   = "backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "backend"
      image = "${data.aws_ecr_repository.ts_backend_repo.repository_url}:latest"
      portMappings = [{
        containerPort = 5000
      }]
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
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

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
    }
  ])
}

# Backend ECS Service
resource "aws_ecs_service" "backend" {
  name            = "backend-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.backend.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = aws_subnet.private.*.id
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  # temp while testing
  load_balancer {
    target_group_arn = aws_lb_target_group.todo_app_target_group.id
    container_name   = "backend"
    container_port   = 5000
  }

  depends_on = [aws_lb.todo_app_lb]

}

# Database ECS Service
resource "aws_ecs_service" "database" {
  name            = "database-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.database.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = aws_subnet.private.*.id
    security_groups = [aws_security_group.ecs_tasks.id]
  }
}
