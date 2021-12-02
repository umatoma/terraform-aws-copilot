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
}

provider "aws" {
  region = "ap-northeast-1"
}

module "app" {
  source = "../modules/app"
  app_name = local.app_name
}

module "app_svc_rdws" {
  source = "../modules/app_svc"
  app_name = local.app_name
  svc_name = "rdws"
}

module "app_svc_lbws" {
  source = "../modules/app_svc"
  app_name = local.app_name
  svc_name = "lbws"
}

module "app_svc_bs" {
  source = "../modules/app_svc"
  app_name = local.app_name
  svc_name = "bs"
}

module "app_svc_ws" {
  source = "../modules/app_svc"
  app_name = local.app_name
  svc_name = "ws"
}

module "app_job_sj" {
  source = "../modules/app_job"
  app_name = local.app_name
  job_name = "sj"
}
