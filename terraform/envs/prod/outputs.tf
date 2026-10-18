output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "ecs_subnet_ids" {
  value = module.network.ecs_subnet_ids
}

output "db_subnet_ids" {
  value = module.network.db_subnet_ids
}