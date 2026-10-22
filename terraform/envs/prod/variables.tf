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

variable "allow_destroy" {
  type        = bool
  default     = false
  description = "Practice mode: turns off deletion protection and lets destroy empty buckets and registries."
}

variable "budget_email" {
  type        = string
  description = "Email for AWS Budgets alerts (set in terraform.tfvars, never committed)"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t4g.micro"
  description = "RDS instance class (override in terraform.tfvars for cheap practice runs)"
}

variable "db_multi_az" {
  type        = bool
  default     = false
  description = "Run a standby database in a second zone (override to false for practice runs)"
}

variable "image_tag" {
  type        = string
  description = "Container image tag to deploy (set in terraform.tfvars)"
}
