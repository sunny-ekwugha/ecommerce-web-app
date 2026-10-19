variable "name" {
  type        = string
  description = "Naming prefix, e.g. ecommerce-prod"
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the customer-managed KMS key used to encrypt the topic"
}