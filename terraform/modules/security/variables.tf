variable "name" {
  type        = string
  description = "Naming prefix, e.g. ecommerce-prod"
}

variable "vpc_id" {
  type        = string
  description = "VPC the security groups belong to"
}