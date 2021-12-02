terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

locals {
  app_name = "tf_copilot"
  env_name = "prod"
}

provider "aws" {
  region = "ap-northeast-1"
}

module "env" {
  source = "../modules/env"
  app_name = local.app_name
  env_name = local.env_name
}
