variable "app_name" {
  type = string
}

variable "env_name" {
  type = string
}

variable "job_name" {
  type = string
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

variable "schedule_expression" {
  type = string
}

locals {
  execution_role_name = "${var.app_name}-${var.env_name}-${var.job_name}-execution_role"
  task_role_name = "${var.app_name}-${var.env_name}-${var.job_name}-task_role"
  task_def_log_group_name = "${var.app_name}-${var.env_name}-${var.job_name}"
  task_def_name = "${var.app_name}-${var.env_name}-${var.job_name}"
  task_def_container_name = var.job_name
  ecr_image_name = "${var.app_name}/${var.job_name}"
  ecs_cluster_name = "${var.app_name}-${var.env_name}"
  env_sg_name = "${var.app_name}-${var.env_name}-env"
  event_rule_name = "${var.app_name}-${var.env_name}-${var.job_name}"
  event_role_name = "${var.app_name}-${var.env_name}-${var.job_name}-event_role"
  tags = {
    application = var.app_name
    environment = var.env_name
    job = var.job_name
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
          Resource = format(
            "arn:aws:ssm::%s:%s:parameter/*",
            data.aws_region.this.name,
            data.aws_caller_identity.this.account_id
          )
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
      environment = [
        { name = "APPLICATION_NAME", value = var.app_name },
        { name = "ENVIRONMENT_NAME", value = var.env_name },
        { name = "JOB_NAME", value = var.job_name },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region: data.aws_region.this.name
          awslogs-group: aws_cloudwatch_log_group.this.name
          awslogs-stream-prefix: "job"
        }
      }
    }
  ])
  tags = local.tags
}

##################################################
# EventBridge Rule
##################################################

resource "aws_iam_role" "ecs_scheduled_task" {
  name = local.event_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action = "sts:AssumeRole"
      }
    ]
  })
  inline_policy {
    name = "pass_role"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = "iam:PassRole"
          Resource = [
            aws_iam_role.execution_role.arn,
            aws_iam_role.task_role.arn,
          ]
        }
      ]
    })
  }
  inline_policy {
    name = "run_task"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = "ecs:RunTask"
          Resource = aws_ecs_task_definition.this.arn
          Condition = {
            ArnEquals = {
              "ecs:cluster": data.aws_ecs_cluster.this.arn
            }
          }
        }
      ]
    })
  }
}

resource "aws_cloudwatch_event_rule" "ecs_scheduled_task" {
  name = local.event_rule_name
  schedule_expression = var.schedule_expression
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "ecs_scheduled_task" {
  target_id = "ecs_scheduled_task"
  rule = aws_cloudwatch_event_rule.ecs_scheduled_task.name
  role_arn = aws_iam_role.ecs_scheduled_task.arn
  arn = data.aws_ecs_cluster.this.arn
  ecs_target {
    task_count = 1
    task_definition_arn = aws_ecs_task_definition.this.arn
    platform_version = "LATEST"
    launch_type = "FARGATE"
    propagate_tags = "TASK_DEFINITION"
    network_configuration {
      assign_public_ip = true
      subnets = data.aws_subnet_ids.public.ids
      security_groups = [data.aws_security_group.env.id]
    }
    tags = local.tags
  }
}
