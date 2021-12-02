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

data "aws_route53_zone" "aws" {
  name = "aws.okto.page"
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "3.2.1"

  zone_id = data.aws_route53_zone.aws.id
  domain_name = "aws.okto.page"
  subject_alternative_names = [
    "lbws.aws.okto.page"
  ]
  wait_for_validation = true
}

module "env" {
  source = "../modules/env"
  app_name = local.app_name
  env_name = local.env_name
  certificate_arn = module.acm.acm_certificate_arn
  aliases = [
    {
      zone_id = data.aws_route53_zone.aws.zone_id
      name = "lbws.aws.okto.page"
    }
  ]
}
