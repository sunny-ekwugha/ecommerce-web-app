output "dns_name" {
  value = aws_lb.this.dns_name
}

output "listener_arn" {
  value = aws_lb_listener.http.arn
}

output "target_group_arns" {
  value = { for k, tg in aws_lb_target_group.svc : k => tg.arn }

  # The ECS services must wait until the listener rules exist
  depends_on = [aws_lb_listener_rule.svc]
}