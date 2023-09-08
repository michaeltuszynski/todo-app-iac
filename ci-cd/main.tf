# CodeStar Connection to GitHub
resource "aws_codestarconnections_connection" "github_connection" {
  provider_type = "GitHub"
  name          = "my-github-connection"
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
          Service = "codebuild.amazonaws.com"
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
          "logs:*"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attach" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
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
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}


resource "aws_iam_policy" "codepipeline_policy" {
  name        = "CodePipelineServicePolicy"
  description = "My policy for CodePipeline"

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

# CodeBuild to build the React app
resource "aws_codebuild_project" "react_build" {
  name          = "react-build-project"
  description   = "Builds the React app"
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
      stream_name = "react-build"
    }
  }
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

# CodePipeline
resource "aws_codepipeline" "react_pipeline" {
  name     = "react-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_bucket.bucket
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
        FullRepositoryId     = "${var.github_owner}/${var.github_repo}"
        BranchName           = "main"
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
        ProjectName = aws_codebuild_project.react_build.name
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
          bucket_name = var.todo_app_bucket
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
        BucketName = var.todo_app_bucket
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
          bucket_name = var.todo_app_bucket
          environment_variables = {
            REACT_APP_BACKEND_URL = var.todo_app_backend_url
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
          distribution_id = var.todo_app_cloudfront_distribution_id
        })
      }
    }
  }
}

resource "aws_s3_bucket" "pipeline_bucket" {
  bucket        = "my-react-pipeline-bucket"
  force_destroy = true
}

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
  source_file = "lambda/empty_s3/index.py"
  output_path = var.lambda_empty_s3_output
}

data "archive_file" "lambda_invalidate_cf_zip" {
  depends_on  = [null_resource.delete_old_archive_invalidate_cf]
  type        = "zip"
  source_file = "lambda/invalidate_cf/index.py"
  output_path = var.lambda_invalidate_cf_output
}

data "archive_file" "lambda_write_config_zip" {
  depends_on  = [null_resource.delete_old_archive_write_config]
  type        = "zip"
  source_file = "lambda/write_config/index.py"
  output_path = var.lambda_write_config_output
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



