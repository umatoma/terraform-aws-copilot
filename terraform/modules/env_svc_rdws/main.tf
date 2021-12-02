variable "app_name" {
  type = string
}

variable "env_name" {
  type = string
}

variable "svc_name" {
  type = string
}

variable "port" {
  type = number
  default = 80
}

variable "cpu" {
  type = number
  default = 1024
}

variable "memory" {
  type = number
  default = 2048
}

variable "image_tag" {
  type = string
  default = "latest"
}

variable "topic_names" {
  type = set(string)
  default = []
}

locals {
  access_role_name = "${var.app_name}-${var.env_name}-${var.svc_name}-access_role"
  instance_role_name = "${var.app_name}-${var.env_name}-${var.svc_name}-instance_role"
  app_runner_service_name = "${var.app_name}-${var.env_name}-${var.svc_name}"
  ecr_image_name = "${var.app_name}/${var.svc_name}"
  tags = {
    application = var.app_name
    environment = var.env_name
    service = var.svc_name
  }
}

data "aws_caller_identity" "this" {}

data "aws_ecr_repository" "this" {
  name = local.ecr_image_name
}

data "aws_ecr_image" "this" {
  repository_name = data.aws_ecr_repository.this.name
  image_tag = var.image_tag
}

##################################################
# SNS Topics
##################################################

module "svc_sns_topics" {
  source = "../svc_sns_topics"
  app_name = var.app_name
  env_name = var.env_name
  svc_name = var.svc_name
  topic_names = var.topic_names
}

##################################################
# App Runner
##################################################

resource "aws_iam_role" "access_role" {
  name = local.access_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "build.apprunner.amazonaws.com" }
        Action = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
  ]
  tags = local.tags
}

resource "aws_iam_role" "instance_role" {
  name = local.instance_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "tasks.apprunner.amazonaws.com" }
        Action = "sts:AssumeRole"
      }
    ]
  })
  inline_policy {
    name = "deny_iam_except_tagged_roles"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Deny"
          Action = "iam:*"
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = "sts:AssumeRole"
          Resource = "arn:aws:iam::${data.aws_caller_identity.this.account_id}:role/*"
          Condition = {
            StringEquals: {
              "iam:ResourceTag/application": var.app_name
              "iam:ResourceTag/environment": var.env_name
            }
          }
        }
      ]
    })
  }
  dynamic "inline_policy" {
    for_each = length(var.topic_names) == 0 ? [] : [1]
    content {
      name = "publish_to_sns"
      policy = module.svc_sns_topics.publish_to_sns_policy
    }
  }
  tags = local.tags
}

resource "aws_apprunner_service" "this" {
  service_name = local.app_runner_service_name
  source_configuration {
    authentication_configuration {
      access_role_arn = aws_iam_role.access_role.arn
    }
    image_repository {
      image_configuration {
        port = tostring(var.port)
        runtime_environment_variables = {
          APPLICATION_NAME = var.app_name
          ENVIRONMENT_NAME = var.env_name
          SERVICE_NAME = var.svc_name
          SNS_TOPIC_ARNS = module.svc_sns_topics.topic_arns_env_value
        }
      }
      image_identifier = "${data.aws_ecr_repository.this.repository_url}:${data.aws_ecr_image.this.image_tag}"
      image_repository_type = "ECR"
    }
    auto_deployments_enabled = false
  }
  instance_configuration {
    cpu = var.cpu
    memory = var.memory
    instance_role_arn = aws_iam_role.instance_role.arn
  }
  tags = local.tags
}
