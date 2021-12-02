variable "app_name" {
  type = string
}

variable "svc_name" {
  type = string
}

locals {
  tags = {
    application = var.app_name
    service = var.svc_name
  }
}

resource "aws_ecr_repository" "this" {
  name = "${var.app_name}/${var.svc_name}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = local.tags
}