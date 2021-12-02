variable "app_name" {
  type = string
}

variable "env_name" {
  type = string
}

variable "svc_name" {
  type = string
}

variable "topic_names" {
  type  = set(string)
}

locals {
  tags = {
    application = var.app_name
    environment = var.env_name
    service = var.svc_name
  }
}

data "aws_caller_identity" "this" {}

resource "aws_sns_topic" "this" {
  for_each = var.topic_names
  name = "${var.app_name}-${var.env_name}-${var.svc_name}-${each.key}"
  tags = local.tags
}

resource "aws_sns_topic_policy" "this" {
  for_each = var.topic_names
  arn = aws_sns_topic.this[each.key].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.this.account_id}:root" }
        Action = "sns:Subscribe"
        Resource = aws_sns_topic.this[each.key].arn
        Condition = {
          StringEquals = {
            "sns:Protocol": "sqs"
          }
        }
      }
    ]
  })
}

output "publish_to_sns_policy" {
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = [for k, v in var.topic_names : aws_sns_topic.this[k].arn]
      }
    ]
  })
}

output "topic_arns_env_value" {
  value = jsonencode({for k, v in var.topic_names : k => aws_sns_topic.this[k].arn})
}
