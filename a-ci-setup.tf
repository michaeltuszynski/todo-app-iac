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
