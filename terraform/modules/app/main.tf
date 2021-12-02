variable "app_name" {
  type = string
}

locals {
  tags = {
    application = var.app_name
  }
}

resource "aws_ssm_parameter" "this" {
  name = "/applications/${var.app_name}"
  type = "String"
  value = jsonencode({
    "name": var.app_name
  })
  tags = local.tags
}