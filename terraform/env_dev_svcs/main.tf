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
  env_name = "dev"
}

provider "aws" {
  region = "ap-northeast-1"
}

module "svc_rdws" {
  source = "../modules/env_svc_rdws"
  app_name = local.app_name
  env_name = local.env_name
  svc_name = "rdws"
}

module "svc_lbws" {
  source = "../modules/env_svc_lbws"
  app_name = local.app_name
  env_name = local.env_name
  svc_name = "lbws"
  topic_names = ["hello"]
  alias_names = ["lbws.aws.okto.page"]
}

module "svc_ws" {
  source = "../modules/env_svc_ws"
  app_name = local.app_name
  env_name = local.env_name
  svc_name = "ws"
  topics = [{ name = "hello", svc_name = "lbws" }]
  depends_on = [module.svc_lbws]
}

module "svc_bs" {
  source = "../modules/env_svc_bs"
  app_name = local.app_name
  env_name = local.env_name
  svc_name = "bs"
}

module "job_sj" {
  source = "../modules/env_job_sj"
  app_name = local.app_name
  env_name = local.env_name
  job_name = "sj"
  schedule_expression = "rate(2 minutes)"
}
