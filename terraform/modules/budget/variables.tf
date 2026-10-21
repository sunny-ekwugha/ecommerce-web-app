variable "name" {
  type        = string
  description = "Naming prefix, e.g. ecommerce-prod"
}

variable "email" {
  type        = string
  description = "Address that receives the budget alerts"
}

variable "limit_usd" {
  type        = string
  default     = "10"
  description = "Monthly spend limit in US dollars"
}