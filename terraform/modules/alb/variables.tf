variable "name" {
  type        = string
  description = "Naming prefix, e.g. ecommerce-prod"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets for the internal load balancer (two zones)"
}

variable "security_group_id" {
  type = string
}

variable "allow_destroy" {
  type        = bool
  description = "True for practice runs: no deletion protection"
}