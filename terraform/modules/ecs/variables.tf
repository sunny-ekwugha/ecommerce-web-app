variable "name" {
  type        = string
  description = "Naming prefix, e.g. ecommerce-prod"
}

variable "env" {
  type        = string
  description = "Environment name passed to the services as ENVIRONMENT"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets for the tasks"
}

variable "security_group_id" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arns" {
  type        = map(string)
  description = "Task role ARN per service key: product, cart, user, order"
}

variable "target_group_arns" {
  type        = map(string)
  description = "ALB target group ARN per service key"
}

variable "repository_urls" {
  type        = map(string)
  description = "ECR repository URL per service, keyed like product-service"
}

variable "image_tag" {
  type        = string
  description = "Image tag to deploy"
}

variable "kms_key_arn" {
  type = string
}

variable "products_table_name" {
  type = string
}

variable "carts_table_name" {
  type = string
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "log_retention_days" {
  type    = number
  default = 14
}