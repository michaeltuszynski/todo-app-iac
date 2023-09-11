variable "github_owner" {
  type = string
}

variable "github_frontend_repo" {
  type = string
}

variable "github_backend_repo" {
  type = string
}

variable "github_token" {
  type = string
}

variable "frontend_bucket" {
  type = string
}

variable "cloudfront_distribution_id" {
  type = string
}

variable "region" {
  type = string
}

variable "lambda_empty_s3_output" {
  type    = string
  default = "./ci-cd/lambda/empty_s3/index.zip"
}

variable "lambda_invalidate_cf_output" {
  type    = string
  default = "./ci-cd/lambda/invalidate_cf/index.zip"
}

variable "lambda_write_config_output" {
  type    = string
  default = "./ci-cd/lambda/write_config/index.zip"
}

variable "image_name" {
  type    = string
  default = "backend_app"
}

variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}

variable "db_port" {
  type = number
}

variable "backend_port" {
  type = number
}

variable "app_name" {
  type = string
}

variable "custom_domain_name" {
  type = string
}
