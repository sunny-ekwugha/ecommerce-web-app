variable "name" {
  type = string
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "kms_deletion_window" {
  type    = number
  default = 30
}