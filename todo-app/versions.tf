# versions.tf | Main Configuration

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region                   = var.region
  shared_credentials_files = ["~/.aws/credentials"]

  default_tags {
    tags = {
      Name        = "${var.app_name}-app"
      Environment = var.app_environment
    }
  }
}

provider "random" {}
