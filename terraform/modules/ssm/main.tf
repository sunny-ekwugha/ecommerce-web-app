data "aws_region" "current" {}

locals {
  prefix = "/ecommerce/${var.env}"

  # The order service appends its own paths (/cart, /users/cognito/..., /products/...),
  # so every service URL is the bare ALB base with no path and no trailing slash.
  plain_parameters = {
    "aws/region"          = data.aws_region.current.region
    "db/host"             = var.db_host
    "user-service-url"    = "http://${var.alb_dns_name}"
    "cart-service-url"    = "http://${var.alb_dns_name}"
    "product-service-url" = "http://${var.alb_dns_name}"
    "sns/topic-arn"       = var.sns_topic_arn
  }
}

resource "aws_ssm_parameter" "plain" {
  for_each = local.plain_parameters

  name           = "${local.prefix}/${each.key}"
  type           = "String"
  insecure_value = each.value
}

resource "aws_ssm_parameter" "db_password" {
  name   = "${local.prefix}/db/password"
  type   = "SecureString"
  key_id = var.kms_key_arn
  value  = var.db_password
}