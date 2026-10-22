locals {
  services = {
    product = { port = 8001, path = "/products*", priority = 10 }
    cart    = { port = 8002, path = "/cart*", priority = 20 }
    user    = { port = 8003, path = "/users*", priority = 30 }
    order   = { port = 8004, path = "/orders*", priority = 40 }
  }
}

resource "aws_lb" "this" {
  name                       = "${var.name}-internal"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [var.security_group_id]
  subnets                    = var.subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = !var.allow_destroy
}

resource "aws_lb_target_group" "svc" {
  for_each = local.services

  name                 = "${var.name}-${each.key}"
  port                 = each.value.port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "svc" {
  for_each = local.services

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.svc[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path]
    }
  }
}