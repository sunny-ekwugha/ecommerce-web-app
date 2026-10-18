variable "region" {
  type    = string
  default = "us-east-1"
}

variable "env" {
  type    = string
  default = "prod"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "single_nat_gateway" {
  description = "true = one NAT (cheap, practice). false = one NAT per AZ (production HA)."
  type        = bool
  default     = false
}

variable "cognito_deletion_protection" {
  type    = string
  default = "ACTIVE"
}