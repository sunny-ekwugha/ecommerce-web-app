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