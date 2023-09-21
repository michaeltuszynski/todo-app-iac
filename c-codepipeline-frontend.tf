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
