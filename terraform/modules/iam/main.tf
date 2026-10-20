data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account = data.aws_caller_identity.current.account_id
  region  = data.aws_region.current.region
  ssm_arn = "arn:aws:ssm:${local.region}:${local.account}:parameter/ecommerce/${var.env}"

  # SSM parameters each service reads (taken from each service's config.py)
  services = {
    product = ["aws/region"]
    cart    = ["aws/region"]
    user    = ["aws/region", "db/host", "db/password"]
    order = [
      "aws/region", "db/host", "db/password",
      "user-service-url", "cart-service-url", "product-service-url",
      "sns/topic-arn",
    ]
  }

  kms_actions = [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
    "kms:DescribeKey",
  ]
}

# Only ECS tasks in this account may assume these roles
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

# Execution role: used by ECS itself to pull images and write logs
resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task roles: one per service, used by the application code
resource "aws_iam_role" "task" {
  for_each           = local.services
  name               = "${var.name}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Every service: read only its own SSM parameters
data "aws_iam_policy_document" "ssm" {
  for_each = local.services

  statement {
    sid       = "ReadOwnParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [for p in each.value : "${local.ssm_arn}/${p}"]
  }

  statement {
    sid       = "DecryptSecureStrings"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "ssm" {
  for_each = local.services
  name     = "read-parameters"
  role     = aws_iam_role.task[each.key].id
  policy   = data.aws_iam_policy_document.ssm[each.key].json
}

# product-service: products table
data "aws_iam_policy_document" "product_dynamodb" {
  statement {
    sid       = "ProductsTable"
    actions   = ["dynamodb:GetItem", "dynamodb:Scan", "dynamodb:UpdateItem"]
    resources = [var.products_table_arn]
  }
  statement {
    sid       = "UseKeyViaDynamoDB"
    actions   = local.kms_actions
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "product_dynamodb" {
  name   = "products-table"
  role   = aws_iam_role.task["product"].id
  policy = data.aws_iam_policy_document.product_dynamodb.json
}

# cart-service: cart table
data "aws_iam_policy_document" "cart_dynamodb" {
  statement {
    sid       = "CartTable"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [var.cart_table_arn]
  }
  statement {
    sid       = "UseKeyViaDynamoDB"
    actions   = local.kms_actions
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "cart_dynamodb" {
  name   = "cart-table"
  role   = aws_iam_role.task["cart"].id
  policy = data.aws_iam_policy_document.cart_dynamodb.json
}

# order-service: publish order events
data "aws_iam_policy_document" "order_sns" {
  statement {
    sid       = "PublishOrderEvents"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
  statement {
    sid       = "UseKeyViaSNS"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sns.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "order_sns" {
  name   = "publish-order-events"
  role   = aws_iam_role.task["order"].id
  policy = data.aws_iam_policy_document.order_sns.json
}