# versions.tf | Main Configuration

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region                   = var.region
  shared_credentials_files = ["~/.aws/credentials"]
}

provider "random" {}
