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
  default = 256
}

variable "memory" {
  type = number
  default = 512
}

variable "desired_count" {
  type = number
  default = 1
}

variable "log_retention" {
  type = number
  default = 30
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
  execution_role_name = "${var.app_name}-${var.env_name}-${var.svc_name}-execution_role"
  task_role_name = "${var.app_name}-${var.env_name}-${var.svc_name}-task_role"
  task_def_log_group_name = "${var.app_name}-${var.env_name}-${var.svc_name}"
  task_def_name = "${var.app_name}-${var.env_name}-${var.svc_name}"
  task_def_container_name = var.svc_name
  ecr_image_name = "${var.app_name}/${var.svc_name}"
  ecs_cluster_name = "${var.app_name}-${var.env_name}"
  ecs_service_name = "${var.app_name}-${var.env_name}-${var.svc_name}"
  env_sg_name = "${var.app_name}-${var.env_name}-env"
  discovery_dns_namespace = "${var.env_name}.${var.app_name}.local"
  tags = {
    application = var.app_name
    environment = var.env_name
    service = var.svc_name
  }
}

data "aws_caller_identity" "this" {}

data "aws_region" "this" {}

data "aws_ecr_repository" "this" {
  name = local.ecr_image_name
}

data "aws_ecr_image" "this" {
  repository_name = data.aws_ecr_repository.this.name
  image_tag = var.image_tag
}

data "aws_ecs_cluster" "this" {
  cluster_name = local.ecs_cluster_name
}

data "aws_vpc" "this" {
  tags = {
    application = var.app_name
    environment = var.env_name
  }
}

data "aws_security_group" "env" {
  vpc_id = data.aws_vpc.this.id
  tags = { Name = local.env_sg_name }
}

data "aws_subnet_ids" "public" {
  vpc_id = data.aws_vpc.this.id
  tags = { public = "true" }
}

data "aws_service_discovery_dns_namespace" "this" {
  name = local.discovery_dns_namespace
  type = "DNS_PRIVATE"
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
# ECS Task Definition
##################################################

resource "aws_iam_role" "execution_role" {
  name = local.execution_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]
  inline_policy {
    name = "secrets"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = "ssm:GetParameters"
          Resource = "arn:aws:ssm::${data.aws_region.this.name}:${data.aws_caller_identity.this.account_id}:parameter/*"
          Condition = {
            StringEquals: {
              "ssm:ResourceTag/application": var.app_name
              "ssm:ResourceTag/environment": var.env_name
            }
          }
        }
      ]
    })
  }
  tags = local.tags
}

resource "aws_iam_role" "task_role" {
  name = local.task_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
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
  inline_policy {
    name = "execute_command"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenDataChannel",
          ],
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogStream",
            "logs:DescribeLogGroups",
            "logs:DescribeLogStreams",
            "logs:PutLogEvents",
          ],
          Resource = "*"
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

resource "aws_cloudwatch_log_group" "this" {
  name = local.task_def_log_group_name
  retention_in_days = var.log_retention
  tags = local.tags
}

resource "aws_ecs_task_definition" "this" {
  family = local.task_def_name
  network_mode = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = var.cpu
  memory = var.memory
  execution_role_arn = aws_iam_role.execution_role.arn
  task_role_arn = aws_iam_role.task_role.arn
  container_definitions = jsonencode([
    {
      name = local.task_def_container_name
      image = "${data.aws_ecr_repository.this.repository_url}:${data.aws_ecr_image.this.image_tag}"
      portMappings = [
        { containerPort: var.port }
      ]
      environment = [
        { name = "APPLICATION_NAME", value = var.app_name },
        { name = "ENVIRONMENT_NAME", value = var.env_name },
        { name = "SERVICE_NAME", value = var.svc_name },
        { name = "SNS_TOPIC_ARNS", value = module.svc_sns_topics.topic_arns_env_value },
        { name = "SERVICE_DISCOVERY_ENDPOINT", value = local.discovery_dns_namespace },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region: data.aws_region.this.name
          awslogs-group: aws_cloudwatch_log_group.this.name
          awslogs-stream-prefix: "service"
        }
      }
    }
  ])
  tags = local.tags
}

##################################################
# Service Discovery
##################################################

resource "aws_service_discovery_service" "this" {
  name = var.svc_name
  dns_config {
    namespace_id = data.aws_service_discovery_dns_namespace.this.id
    routing_policy = "MULTIVALUE"
    dns_records {
      ttl = 10
      type = "A"
    }
    dns_records {
      ttl = 10
      type = "SRV"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
  tags = local.tags
}

##################################################
# ECS Service
##################################################

resource "aws_ecs_service" "this" {
  name = local.ecs_service_name
  platform_version = "LATEST"
  cluster = data.aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count = var.desired_count
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent = 200
  propagate_tags = "SERVICE"
  enable_execute_command = true
  launch_type = "FARGATE"
  deployment_circuit_breaker {
    enable = true
    rollback = true
  }
  network_configuration {
    assign_public_ip = true
    subnets = data.aws_subnet_ids.public.ids
    security_groups = [data.aws_security_group.env.id]
  }
  service_registries {
    registry_arn = aws_service_discovery_service.this.arn
    port = var.port
  }
  tags = local.tags
}
