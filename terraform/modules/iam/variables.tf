variable "name" {
  type        = string
  description = "Naming prefix, e.g. ecommerce-prod"
}

variable "env" {
  type        = string
  description = "Environment name, used in SSM parameter paths"
}

variable "kms_key_arn" {
  type        = string
  description = "Customer-managed KMS key protecting tables, parameters and the topic"
}

variable "products_table_arn" {
  type = string
}

variable "cart_table_arn" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}