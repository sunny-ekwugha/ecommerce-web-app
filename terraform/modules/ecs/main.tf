data "aws_region" "current" {}

locals {
  services = {
    product = { port = 8001, env = { PRODUCTS_TABLE = var.products_table_name } }
    cart    = { port = 8002, env = { CARTS_TABLE = var.carts_table_name } }
    user    = { port = 8003, env = {} }
    order   = { port = 8004, env = {} }
  }

  common_env = {
    ENVIRONMENT = var.env
    AWS_REGION  = data.aws_region.current.region
  }
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_cloudwatch_log_group" "svc" {
  for_each = local.services

  name              = "/ecs/${var.name}/${each.key}-service"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_ecs_task_definition" "svc" {
  for_each = local.services

  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arns[each.key]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "${each.key}-service"
    image        = "${var.repository_urls["${each.key}-service"]}:${var.image_tag}"
    essential    = true
    user         = "1000:1000"
    portMappings = [{ containerPort = each.value.port, protocol = "tcp" }]
    environment  = [for k, v in merge(local.common_env, each.value.env) : { name = k, value = v }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.svc[each.key].name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "svc" {
  for_each = local.services

  name            = "${each.key}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.svc[each.key].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arns[each.key]
    container_name   = "${each.key}-service"
    container_port   = each.value.port
  }
}