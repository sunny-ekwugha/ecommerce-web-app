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

output "cognito_user_pool_id" { value = module.cognito.user_pool_id }
output "cognito_client_id" { value = module.cognito.client_id }
output "cognito_issuer" { value = module.cognito.issuer }