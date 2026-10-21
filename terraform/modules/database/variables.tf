variable "name" {
  type        = string
  description = "Naming prefix, e.g. ecommerce-prod"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private database subnets"
}

variable "security_group_id" {
  type        = string
  description = "Security group that allows PostgreSQL from the ECS tasks"
}

variable "kms_key_arn" {
  type        = string
  description = "Customer-managed key for storage and log encryption"
}

variable "allow_destroy" {
  type        = bool
  description = "True for practice runs: no deletion protection and no final snapshot"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "db_name" {
  type    = string
  default = "ecommercedb"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "backup_retention_days" {
  type    = number
  default = 14
}

variable "log_retention_days" {
  type    = number
  default = 14
}