# Ask AWS for the default minor version of PostgreSQL 16 and its parameter group family
data "aws_rds_engine_version" "pg" {
  engine       = "postgres"
  version      = "16"
  default_only = true
}

# Alphanumeric only, so it is safe in connection strings
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.name}-postgres"
  family = data.aws_rds_engine_version.pg.parameter_group_family

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

# Created here so that destroy removes them (RDS would otherwise create them and leave them behind)
resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/instance/${var.name}-postgres/postgresql"
  retention_in_days = var.backup_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_cloudwatch_log_group" "upgrade" {
  name              = "/aws/rds/instance/${var.name}-postgres/upgrade"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_db_instance" "this" {
  identifier = "${var.name}-postgres"

  engine         = "postgres"
  engine_version = data.aws_rds_engine_version.pg.version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  db_name  = var.db_name
  username = "postgres"
  password = random_password.db.result
  port     = 5432

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period    = var.log_retention_days
  backup_window              = "03:00-04:00"
  maintenance_window         = "sun:05:00-sun:06:00"
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  deletion_protection       = !var.allow_destroy
  skip_final_snapshot       = var.allow_destroy
  final_snapshot_identifier = var.allow_destroy ? null : "${var.name}-postgres-final"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  depends_on = [
    aws_cloudwatch_log_group.postgresql,
    aws_cloudwatch_log_group.upgrade,
  ]

  lifecycle {
    # AWS applies minor upgrades itself, so don't fight it
    ignore_changes = [engine_version]
  }
}