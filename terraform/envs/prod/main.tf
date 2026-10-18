locals {
  name = "ecommerce-${var.env}"
}

module "network" {
  source             = "../../modules/network"
  name               = local.name
  vpc_cidr           = var.vpc_cidr
  az_count           = 2
  single_nat_gateway = var.single_nat_gateway
}

module "cognito" {
  source              = "../../modules/cognito"
  name                = local.name
  deletion_protection = var.cognito_deletion_protection
}

module "frontend" {
  source        = "../../modules/frontend"
  name          = local.name
  images_dir    = "${path.root}/../../../data/product-images"
  force_destroy = var.frontend_force_destroy
}

module "ecr" {
  source       = "../../modules/ecr"
  name         = local.name
  force_delete = var.ecr_force_delete
}

module "data" {
  source              = "../../modules/data"
  name                = local.name
  deletion_protection = var.data_deletion_protection
}

output "products_table" { value = module.data.products_table_name }
output "cart_table" { value = module.data.cart_table_name }
output "kms_key_arn" { value = module.data.kms_key_arn }