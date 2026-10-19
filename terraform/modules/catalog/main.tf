locals {
  products = { for p in jsondecode(file(var.products_file)) : p.product_id => p }
}

resource "aws_dynamodb_table_item" "product" {
  for_each   = local.products
  table_name = var.table_name
  hash_key   = "product_id"

  item = jsonencode({
    product_id  = { S = each.value.product_id }
    name        = { S = each.value.name }
    description = { S = each.value.description }
    price       = { N = tostring(each.value.price) }
    stock       = { N = tostring(each.value.stock) }
    category    = { S = each.value.category }
    image_url   = { S = "${var.image_base_url}/images/products/${each.value.product_id}.jpg" }
  })

  lifecycle {
    ignore_changes = [item]
  }
}