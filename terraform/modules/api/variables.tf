variable "name" {
  type        = string
  description = "Naming prefix, e.g. ecommerce-prod"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets for the VPC link"
}

variable "security_group_id" {
  type        = string
  description = "Security group for the VPC link"
}

variable "listener_arn" {
  type        = string
  description = "ARN of the internal ALB listener"
}

variable "cognito_issuer" {
  type = string
}

variable "cognito_client_id" {
  type = string
}

variable "allowed_origin" {
  type        = string
  description = "The one browser origin allowed to call the API, e.g. https://xxxx.cloudfront.net"
}

variable "throttle_rate" {
  type    = number
  default = 50
}

variable "throttle_burst" {
  type    = number
  default = 100
}

variable "log_retention_days" {
  type    = number
  default = 14
}