variable "app_name" {
  type = string
}

variable "env_name" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "extra_certificate_arns" {
  type = list(string)
  default = []
}

variable "aliases" {
  type = list(object({
    zone_id = string
    name = string
  }))
  default = []
}

locals {
  vpc_name = "${var.app_name}-${var.env_name}"
  env_sg_name = "${var.app_name}-${var.env_name}-env"
  ecs_cluster_name = "${var.app_name}-${var.env_name}"
  lb_name = replace("${var.app_name}-${var.env_name}-public", "_", "-")
  lb_sg_name = "${var.app_name}-${var.env_name}-lb"
  discovery_dns_namespace = "${var.env_name}.${var.app_name}.local"
  extra_certificate_arns = toset(var.extra_certificate_arns)
  aliases = {for a in var.aliases : a.name => {
    zone_id = a.zone_id
    name = a.name
  }}
  tags = {
    application = var.app_name
    environment = var.env_name
  }
}

data "aws_region" "this" {}

##################################################
# Systems Manager Parameter Store
##################################################

resource "aws_ssm_parameter" "this" {
  name = "/applications/${var.app_name}/environments/${var.env_name}"
  type = "String"
  value = jsonencode({
    "name": var.env_name,
    "app_name": var.app_name,
  })
  tags = local.tags
}

##################################################
# VPC
##################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.11.0"

  name = local.vpc_name
  cidr = "10.0.0.0/16"
  azs = ["${data.aws_region.this.name}a", "${data.aws_region.this.name}c"]
  public_subnets = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_tags = { public: "true" }
  private_subnet_tags = { public: "false" }
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = local.tags
}

resource "aws_security_group" "lb" {
  name = local.lb_sg_name
  vpc_id = module.vpc.vpc_id
  ingress {
    description = "Allow HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow HTTPS"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = ""
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge({ Name: local.lb_sg_name }, local.tags)
}

resource "aws_security_group" "env" {
  name = local.env_sg_name
  vpc_id = module.vpc.vpc_id
  ingress {
    description = ""
    from_port = 0
    to_port = 0
    protocol = "-1"
    self = true
  }
  ingress {
    description = "Allow ALB to Environment"
    from_port = 0
    to_port = 0
    protocol = "-1"
    security_groups = [aws_security_group.lb.id]
  }
  egress {
    description = ""
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge({ Name: local.env_sg_name }, local.tags)
}

##################################################
# ECS Cluster
##################################################

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "3.4.1"

  name = local.ecs_cluster_name
  container_insights = true
  capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy = [
    { capacity_provider = "FARGATE" }
  ]
  tags = local.tags
}

##################################################
# Public ALB
##################################################

resource "aws_lb" "this" {
  name = local.lb_name
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.lb.id]
  subnets = module.vpc.public_subnets
  tags = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port = "80"
  protocol = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port = "443"
      protocol = "HTTPS"
      status_code = "HTTP_301"
    }
  }
  tags = local.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port = "443"
  protocol = "HTTPS"
  certificate_arn = var.certificate_arn
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "503 Service Temporarily Unavailable"
      status_code = "503"
    }
  }
  tags = local.tags
}

resource "aws_alb_listener_certificate" "https" {
  for_each = local.extra_certificate_arns
  listener_arn = aws_lb.this.arn
  certificate_arn = each.key
}

resource "aws_route53_record" "this" {
  for_each = local.aliases
  zone_id = local.aliases[each.key].zone_id
  name = local.aliases[each.key].name
  type = "A"
  alias {
    name = aws_lb.this.dns_name
    zone_id = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

##################################################
# Service Discovery
##################################################

resource "aws_service_discovery_private_dns_namespace" "this" {
  name = local.discovery_dns_namespace
  vpc = module.vpc.vpc_id
}