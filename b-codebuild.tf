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
