variable "name" {
  type = string
}

variable "services" {
  type    = set(string)
  default = ["product-service", "cart-service", "order-service", "user-service"]
}

variable "force_delete" {
  type    = bool
  default = false
}