## IAM Roles
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
         var.bucket_arn,
          "${var.bucket_arn}/*"
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
      Resource = "${var.secret_arn}"
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

## IAM Role Policy Attachments
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