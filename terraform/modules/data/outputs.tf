output "kms_key_arn" {
  value = aws_kms_key.data.arn
}

output "kms_alias" {
  value = aws_kms_alias.data.name
}

output "products_table_name" {
  value = aws_dynamodb_table.products.name
}

output "products_table_arn" {
  value = aws_dynamodb_table.products.arn
}

output "cart_table_name" {
  value = aws_dynamodb_table.cart.name
}

output "cart_table_arn" {
  value = aws_dynamodb_table.cart.arn
}