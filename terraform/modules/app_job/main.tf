variable "app_name" {
  type = string
}

variable "job_name" {
  type = string
}

locals {
  tags = {
    application = var.app_name
    job = var.job_name
  }
}

resource "aws_ecr_repository" "this" {
  name = "${var.app_name}/${var.job_name}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = local.tags
}