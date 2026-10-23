output "parameter_names" {
  value = concat(
    [for p in aws_ssm_parameter.plain : p.name],
    [aws_ssm_parameter.db_password.name],
  )
}