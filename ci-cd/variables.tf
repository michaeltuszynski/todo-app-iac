
variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_token" {
  type = string
}

variable "todo_app_bucket" {
  type = string
}

variable "todo_app_cloudfront_distribution_id" {
  type = string
}

variable "todo_app_backend_url" {
  type = string
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "lambda_empty_s3_output" {
  type    = string
  default = "lambda/empty_s3/index.zip"
}

variable "lambda_invalidate_cf_output" {
  type    = string
  default = "lambda/invalidate_cf/index.zip"
}

variable "lambda_write_config_output" {
  type    = string
  default = "lambda/write_config/index.zip"
}
