variable "env" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "db_host" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "alb_dns_name" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}