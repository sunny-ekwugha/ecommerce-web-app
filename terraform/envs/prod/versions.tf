terraform {
  required_version = "~> 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial backend config. The bucket name lives in backend.hcl (gitignored).
  backend "s3" {
    key          = "ecommerce/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "ecommerce"
      Env       = var.env
      ManagedBy = "terraform"
    }
  }
}