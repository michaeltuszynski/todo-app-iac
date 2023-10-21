# main.tf
# This fetches the currently available availability zones for use in VPC configuration.
data "aws_availability_zones" "available_zones" {
  state = "available"
}

# Define the main VPC.  Be sure to choose an appropriate private CIDR block. Since this will be hosting a web application, we leave DNS enabled.
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "Name Tag Value"
  }
}

# Define the public subnets.   We use the cidrsubnet helper to carve out appropriately scoped /24 subnets
resource "aws_subnet" "public" {
  count                   = 2
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, 2 + count.index)
  availability_zone       = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id                  = aws_vpc.this.id
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index}"
  }
}

# Define the private subnets.   We use the cidrsubnet helper to carve out appropriately scoped /24 subnets
resource "aws_subnet" "private" {
  count             = 2
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id            = aws_vpc.this.id

  tags = {
    Name = "private-subnet-${count.index}"
  }
}

# Define an internet gateway
resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.this.id
}

# Define a route table that routes the public subnet through the gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

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

# NAT Gateways requires an Elastic IP address (EIP)
resource "aws_eip" "nat" {
  depends_on = [aws_internet_gateway.gateway]
}

resource "aws_nat_gateway" "nat_gateway" {
  subnet_id     = aws_subnet.public[0].id
  allocation_id = aws_eip.nat.id
}

# Define the routes that let resources in the private subnet communication with the public internet route (0.0.0.0/0)
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.this.id

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
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private.*.id
  tags = {
    Name = "my-s3-vpc-endpoint"
  }
}

# VPC Endpoint for Secrets Manager
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.us-east-1.secretsmanager"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_tasks.id]
  subnet_ids          = aws_subnet.private.*.id
  private_dns_enabled = true

  tags = {
    Name = "my-secretsmanager-vpc-endpoint"
  }
}

# VPC Endpoint for ECR (Docker)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.us-east-1.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_tasks.id]
  subnet_ids          = aws_subnet.private.*.id
  private_dns_enabled = true
  tags = {
    Name = "my-ECR-docker-vpc-endpoint"
  }
}

# VPC Endpoint for ECR (API)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.us-east-1.ecr.api"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_tasks.id]
  subnet_ids          = aws_subnet.private.*.id
  private_dns_enabled = true
  tags = {
    Name = "my-ECR-API-vpc-endpoint"
  }
}

# VPC Endpoint for CloudWatch Logs
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.us-east-1.logs"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.ecs_tasks.id]
  subnet_ids          = aws_subnet.private.*.id
  private_dns_enabled = true
  tags = {
    Name = "my-cloudwatch-vpc-endpoint"
  }
}
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
## Define a Secret in AWS Secrets Manager to use with the database
resource "random_integer" "password_length" {
  min = 8
  max = 16
}

resource "random_password" "db_password" {
  length  = random_integer.password_length.result
  special = false
}

# AWS requires that named entities like secrets have unique names.   Random pet generates a readable string to append to names to ensure uniqueness.
resource "random_pet" "secret_name" {
  length = 2
}

resource "aws_secretsmanager_secret" "docdb_credentials" {
  name = "my-docdb_credentials-${random_pet.secret_name.id}"
}

# This defines the format the secret is stored as, in this case JSON.  Secrets are versioned, allowing for credential rotation.
resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id     = aws_secretsmanager_secret.docdb_credentials.id
  secret_string = "{\"username\":\"root\", \"password\":\"${random_password.db_password.result}\"}"
}

## Define DocumentDB (Mongo on AWS).  DocumentDB instances are created within clusters.
resource "aws_docdb_cluster" "docdb_cluster" {
  cluster_identifier              = "my-docdb-cluster"
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
  identifier         = "my-docdb-instance"
  cluster_identifier = aws_docdb_cluster.docdb_cluster.cluster_identifier
  instance_class     = "db.r5.large"
}

resource "aws_docdb_subnet_group" "default" {
  name       = "my-subnet-group"
  subnet_ids = aws_subnet.private.*.id

  tags = {
    Name = "default"
  }
}

resource "aws_security_group" "docdb_sg" {
  name        = "my-docdb_sg"
  description = "Security group for DocumentDB"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
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

resource "aws_iam_role" "docdb_role" {
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

resource "aws_ecr_repository" "backend" {
  name                 = "backend_app"
  image_tag_mutability = "MUTABLE"

  # Enable image scanning on push
  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "cleanup_policy" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire images older than 30 days"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Define the ECS Cluster - the top level of the ECS hierarchy.   Clusters contain services.
resource "aws_ecs_cluster" "todo_api_cluster" {
  name = "my-cluster"
}

# Define the backend Task Definition.  A task definition is a blueprint that describes how a Docker container should launch and run, specifying parameters like the Docker image, memory and CPU requirements, network mode, and more.
resource "aws_ecs_task_definition" "backend" {
  family                   = "backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]  # Fargate is AWS's "serverless" container infrastructure
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:latest"
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
          name  = "DB_PORT",
          value = "27017"
        },
        {
          name  = "NODEPORT",
          value = "5000"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_tasks.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])

  depends_on = [
     aws_cloudwatch_log_group.ecs_tasks,
     aws_docdb_cluster_instance.docdb_instance,
     aws_secretsmanager_secret_version.db_secret_version,
     aws_ecr_repository.backend,
     aws_iam_role.ecs_task_role,
     aws_iam_role.ecs_execution_role
  ]
}

# Backend ECS Service
resource "aws_ecs_service" "backend" {
  name            = "backend-service"
  cluster         = aws_ecs_cluster.todo_api_cluster.id
  task_definition = aws_ecs_task_definition.backend.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = aws_subnet.private.*.id
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.default.arn
    container_name   = "backend"
    container_port   = "5000"
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  lifecycle {
    ignore_changes = [desired_count] //used to avoid Terraform to reset the desired_count if auto-scaling changes it.
  }

  depends_on = [
     aws_ecs_cluster.todo_api_cluster,
     aws_ecs_task_definition.backend,
     aws_subnet.private,
     aws_security_group.ecs_tasks,
     aws_lb_target_group.default
  ]
}

# ECS Security Group for Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "my-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.this.id

  # Inbound rules
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  # Outbound rules (default allows all outbound traffic)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "my-ecs-tasks-sg"
  }
}

## ECS Cloudwatch Log Group
resource "aws_cloudwatch_log_group" "ecs_tasks" {
  name = "my-ecs-tasks-logs"
}

# IAM Role for Tasks
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

# IAM Role for Task Execution
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

## IAM Policies
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

resource "aws_iam_policy" "ecs_secrets_access" {
  name        = "ECSAccessToSecrets"
  description = "Allow ECS tasks to retrieve secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "secretsmanager:GetSecretValue"
      ],
      Resource = "${aws_secretsmanager_secret.docdb_credentials.arn}"
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
          "docdb:*",
          "rds:*"
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
         aws_s3_bucket.frontend.arn,
          "${aws_s3_bucket.frontend.arn}/*"
        ]
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
  role       = aws_iam_role.docdb_role.name
  policy_arn = aws_iam_policy.ecs_docdb_access.arn
}

resource "aws_iam_role_policy_attachment" "custom_s3_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.s3_policy_permissions.arn
}







# main.tf | Frontend Infrastructure (S3, CloudFront, Route53)

## Create an S3 Bucket
resource "random_pet" "bucket_name" {
  length = 2
}

locals {
  www_subdomain = "www.${local.domain_name}"
}

resource "aws_s3_bucket" "frontend" {
  bucket        = "my-bucket-${random_pet.bucket_name.id}"
  force_destroy = true
}

resource "aws_s3_bucket_cors_configuration" "this" {
  bucket = aws_s3_bucket.frontend.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "DELETE", "GET", "HEAD"]
    allowed_origins = ["https://${local.www_subdomain}", "https://backend.${local.domain_name}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_website_configuration" "frontend_website" {
  bucket = aws_s3_bucket.frontend.bucket
  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.frontend.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "my Cloudfront Distribution"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.frontend.id

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

  aliases = [local.www_subdomain]

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
}

resource "aws_route53_record" "cloudfront_alias_record" {
  zone_id = local.hosted_zone_id
  name    = "${local.domain_name}."
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_cloudfront_alias_record" {
  zone_id = local.hosted_zone_id
  name    = "${local.www_subdomain}."
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
  bucket = aws_s3_bucket.frontend.id

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
        Resource = "arn:aws:s3:::${aws_s3_bucket.frontend.bucket}/*"
      }
    ]
  })
}

# Needed for Cloudfront certificates, only supported in us-east-1
# provider "aws" {
#   alias  = "east"
#   region = "us-east-1"
# }

# data "aws_acm_certificate" "cf_distro" {
#   domain      = local.domain_name
#   most_recent = true

#   provider = aws.east
# }
variable "lambda_empty_s3_output" {
  type    = string
  default = "./lambda/empty_s3/index.zip"
}

variable "lambda_invalidate_cf_output" {
  type    = string
  default = "./lambda/invalidate_cf/index.zip"
}

variable "lambda_write_config_output" {
  type    = string
  default = "./lambda/write_config/index.zip"
}

variable "image_name" {
  type    = string
  default = "backend_app"
}

locals {
  backend_url = "backend.${local.domain_name}"
}

# CodeStar Connection to GitHub
resource "aws_codestarconnections_connection" "github_connection" {
  provider_type = "GitHub"
  name          = "github-connection"
}

//Frontend CI Lambda Functions
resource "null_resource" "delete_old_archive_emptys3" {
  provisioner "local-exec" {
    command = "rm -f ${var.lambda_empty_s3_output}"
  }
  triggers = {
    always_recreate = "${timestamp()}" # Ensure it runs every time
  }
}

resource "null_resource" "delete_old_archive_invalidate_cf" {
  provisioner "local-exec" {
    command = "rm -f ${var.lambda_invalidate_cf_output}"
  }
  triggers = {
    always_recreate = "${timestamp()}" # Ensure it runs every time
  }
}

resource "null_resource" "delete_old_archive_write_config" {
  provisioner "local-exec" {
    command = "rm -f ${var.lambda_write_config_output}"
  }
  triggers = {
    always_recreate = "${timestamp()}" # Ensure it runs every time
  }
}

data "archive_file" "lambda_empty_s3_zip" {
  depends_on  = [null_resource.delete_old_archive_emptys3]
  type        = "zip"
  source_file = "./lambda/empty_s3/index.py"
  output_path = var.lambda_empty_s3_output
}

data "archive_file" "lambda_invalidate_cf_zip" {
  depends_on  = [null_resource.delete_old_archive_invalidate_cf]
  type        = "zip"
  source_file = "./lambda/invalidate_cf/index.py"
  output_path = var.lambda_invalidate_cf_output
}

data "archive_file" "lambda_write_config_zip" {
  depends_on  = [null_resource.delete_old_archive_write_config]
  type        = "zip"
  source_file = "./lambda/write_config/index.py"
  output_path = var.lambda_write_config_output
}

resource "aws_cloudwatch_log_group" "empty_s3_log_group" {
  name = "/aws/lambda/${aws_lambda_function.empty_s3.function_name}"
}

resource "aws_cloudwatch_log_group" "invalidate_cf_log_group" {
  name = "/aws/lambda/${aws_lambda_function.invalidate_cf.function_name}"
}

resource "aws_cloudwatch_log_group" "write_config_log_group" {
  name = "/aws/lambda/${aws_lambda_function.write_config.function_name}"
}

resource "aws_lambda_function" "empty_s3" {
  function_name = "emptyS3Function"
  handler       = "index.lambda_handler"
  runtime       = "python3.8"
  timeout       = 60

  filename         = data.archive_file.lambda_empty_s3_zip.output_path
  source_code_hash = data.archive_file.lambda_empty_s3_zip.output_base64sha256

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "invalidate_cf" {
  function_name = "invalidateCFFunction"
  handler       = "index.lambda_handler"
  runtime       = "python3.8"
  timeout       = 60

  filename         = data.archive_file.lambda_invalidate_cf_zip.output_path
  source_code_hash = data.archive_file.lambda_invalidate_cf_zip.output_base64sha256

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "write_config" {
  function_name = "writeConfigFunction"
  handler       = "index.lambda_handler"
  runtime       = "python3.8"
  timeout       = 60

  filename         = data.archive_file.lambda_write_config_zip.output_path
  source_code_hash = data.archive_file.lambda_write_config_zip.output_base64sha256

  role = aws_iam_role.lambda_exec_role.arn
}


## IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "AWSLambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_exec_policy" {
  name        = "codepipeline_lambda_exec_policy"
  description = "Allows Lambda to access necessary resources"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*",
        Effect   = "Allow"
      },
      {
        Action = [
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:PutObject"
        ],
        Resource = "*",
        Effect   = "Allow"
      },
      {
        Action = [
          "codepipeline:PutJobSuccessResult",
          "codepipeline:PutJobFailureResult"
        ],
        Resource = "*",
        Effect   = "Allow"
      },
      {
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation",
          "cloudfront:ListInvalidations"
        ],
        Resource = "*",
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_exec_policy.arn
}

# IAM Role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "CodeBuildServiceRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = ["codebuild.amazonaws.com"]
        }
      }
    ]
  })
}

resource "aws_iam_policy" "codebuild_policy" {
  name        = "CodeBuildPolicy"
  description = "Allows CodeBuild to access necessary resources"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "codestar-connections:UseConnection"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "logs:*",
          "codedeploy:*"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      # {
      #   Action = [
      #     "ecs:*"
      #   ],
      #   Effect   = "Allow",
      #   Resource = "*"
      # },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attach" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

resource "aws_iam_policy" "codebuild_ecr" {
  name        = "CodeBuildECRPolicy"
  description = "Allows CodeBuild to interact with ECR"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:GetAuthorizationToken",
        ],
        Resource = "*"
      },
      # {
      #   Effect   = "Allow",
      #   Action   = "ecs:*",
      #   Resource = "*"
      # }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_ecr_attach" {
  policy_arn = aws_iam_policy.codebuild_ecr.arn
  role       = aws_iam_role.codebuild_role.name
}

# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "CodePipelineServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = ["codepipeline.amazonaws.com"]
        }
      }
    ]
  })
}

resource "aws_iam_policy" "codepipeline_policy" {
  name        = "CodePipelineServicePolicy"
  description = "Policy for CodePipeline"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "codestar-connections:UseConnection"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codedeploy:*",
          "iam:PassRole"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "ecs:*"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "logs:*"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "lambda:InvokeFunction"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy_attach" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
}
# CodeBuild to build the Fronend app
resource "aws_codebuild_project" "frontend" {
  name          = "frontend-build-project"
  description   = "Builds the Frontend Website"
  build_timeout = "15"
  service_role  = aws_iam_role.codebuild_role.arn

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    type         = "LINUX_CONTAINER"
    image        = "aws/codebuild/standard:5.0"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codepipeline_log_group.name
      stream_name = "frontend-build"
    }
  }
}

# CodeBuild to build the backend app
resource "aws_codebuild_project" "backend" {
  name          = "my-backend-build-project"
  description   = "Builds the NodeJS/Express app"
  build_timeout = "15"
  service_role  = aws_iam_role.codebuild_role.arn

  source {
    type = "CODEPIPELINE"
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        pre_build = {
          commands = [
            "echo Logging in to Amazon ECR...",
            "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.backend.repository_url}"
          ]
        }
        install = {
          runtime-versions = {
            nodejs = "14"
          }
          commands = [
            "n 18",
            "yarn install"
          ]
        }
        build = {
          commands = [
            "yarn build",
            "echo Building the Docker image...",
            "docker build -t ${aws_ecr_repository.backend.repository_url}:latest .",
            "docker push ${aws_ecr_repository.backend.repository_url}:latest",
            "printf '[{\"name\":\"backend\",\"imageUri\":\"${aws_ecr_repository.backend.repository_url}:latest\"}]' > imagedefinitions.json",
            "cat imagedefinitions.json"
          ]
        }
      }
      artifacts = {
        files = [
          "**/*"
        ]
      }
    })
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    type                        = "LINUX_CONTAINER"
    image                       = "aws/codebuild/standard:5.0"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codepipeline_log_group.name
      stream_name = "backend-build"
    }
  }
}
# S3 Buckets for CodePipeline

locals {
  github_owner = "michaeltuszynski"
  github_frontend_repo = "todo-app-frontend"
}

resource "aws_s3_bucket" "frontend_pipeline" {
  bucket        = "frontend-pipeline-${random_pet.bucket_name.id}"
  force_destroy = true
}

resource "aws_cloudwatch_log_group" "codepipeline_log_group" {
  name = "codepipeline-log-group"
}

resource "aws_cloudwatch_event_rule" "codepipeline_events" {
  name        = "capture-codepipeline-events"
  description = "Capture all CodePipeline events"

  event_pattern = jsonencode({
    "source" : ["aws.codepipeline"]
  })
}

resource "aws_cloudwatch_event_target" "send_to_cloudwatch_logs" {
  rule      = aws_cloudwatch_event_rule.codepipeline_events.name
  arn       = aws_cloudwatch_log_group.codepipeline_log_group.arn
  target_id = "CodePipelineToCloudWatch"
}

# CodePipeline for frontend app
resource "aws_codepipeline" "frontend" {
  name     = "my-frontend-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.frontend_pipeline.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github_connection.arn
        FullRepositoryId     = "${local.github_owner}/${local.github_frontend_repo}"
        BranchName           = "aws"
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.frontend.name
      }
    }
  }

  stage {
    name = "Cleanup"
    action {
      name             = "EmptyS3Bucket"
      category         = "Invoke"
      owner            = "AWS"
      provider         = "Lambda"
      version          = "1"
      input_artifacts  = []
      output_artifacts = []
      configuration = {
        FunctionName = aws_lambda_function.empty_s3.function_name
        UserParameters = jsonencode({
          bucket_name = aws_s3_bucket.frontend.bucket
        })
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      input_artifacts = ["build_output"]
      version         = "1"
      configuration = {
        BucketName = aws_s3_bucket.frontend.bucket
        Extract    = "true"
      }
    }
  }

  stage {
    name = "PushBackendConfig"
    action {
      name             = "WriteConfig"
      category         = "Invoke"
      owner            = "AWS"
      provider         = "Lambda"
      version          = "1"
      input_artifacts  = []
      output_artifacts = []
      configuration = {
        FunctionName = aws_lambda_function.write_config.function_name
        UserParameters = jsonencode({
          bucket_name = aws_s3_bucket.frontend.bucket
          environment_variables = {
            REACT_APP_BACKEND_URL = local.backend_url
          }
        })
      }
    }
  }

  stage {
    name = "InvalidateCloudFront"
    action {
      name             = "InvalidateCloudFront"
      category         = "Invoke"
      owner            = "AWS"
      provider         = "Lambda"
      version          = "1"
      input_artifacts  = []
      output_artifacts = []
      configuration = {
        FunctionName = aws_lambda_function.invalidate_cf.function_name
        UserParameters = jsonencode({
          distribution_id = aws_cloudfront_distribution.s3_distribution.id
        })
      }
    }
  }
}
locals {
  github_backend_repo = "todo-app-backend"
}

resource "aws_s3_bucket" "backend_pipeline" {
  bucket        = "backend-pipeline-${random_pet.bucket_name.id}"
  force_destroy = true
}

# CodePipeline for backend app
resource "aws_codepipeline" "backend" {
  name     = "my-backend-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.backend_pipeline.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn        = aws_codestarconnections_connection.github_connection.arn
        FullRepositoryId     = "${local.github_owner}/${local.github_backend_repo}"
        BranchName           = "aws"
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.backend.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["build_output"]
      version         = "1"
      configuration = {
        ClusterName = aws_ecs_cluster.todo_api_cluster.name
        ServiceName = aws_ecs_service.backend.name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}
