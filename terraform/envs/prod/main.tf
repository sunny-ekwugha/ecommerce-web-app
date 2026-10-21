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
  deletion_protection = var.allow_destroy ? "INACTIVE" : "ACTIVE"
}

module "frontend" {
  source        = "../../modules/frontend"
  name          = local.name
  images_dir    = "${path.root}/../../../data/product-images"
  force_destroy = var.allow_destroy
}

module "ecr" {
  source       = "../../modules/ecr"
  name         = local.name
  force_delete = var.allow_destroy
}

module "data" {
  source              = "../../modules/data"
  name                = local.name
  deletion_protection = !var.allow_destroy
}

output "products_table" { value = module.data.products_table_name }
output "cart_table" { value = module.data.cart_table_name }
output "kms_key_arn" { value = module.data.kms_key_arn }

module "catalog" {
  source         = "../../modules/catalog"
  table_name     = module.data.products_table_name
  products_file  = "${path.root}/../../../data/products.json"
  image_base_url = "https://${module.frontend.distribution_domain}"
}

module "messaging" {
  source      = "../../modules/messaging"
  name        = local.name
  kms_key_arn = module.data.kms_key_arn
}

module "iam" {
  source             = "../../modules/iam"
  name               = local.name
  env                = var.env
  kms_key_arn        = module.data.kms_key_arn
  products_table_arn = module.data.products_table_arn
  cart_table_arn     = module.data.cart_table_arn
  sns_topic_arn      = module.messaging.topic_arn
}

module "budget" {
  source = "../../modules/budget"
  name   = local.name
  email  = var.budget_email
}

module "security" {
  source = "../../modules/security"
  name   = local.name
  vpc_id = module.network.vpc_id
}