output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "ecs_subnet_ids" {
  value = aws_subnet.ecs[*].id
}

output "db_subnet_ids" {
  value = aws_subnet.db[*].id
}