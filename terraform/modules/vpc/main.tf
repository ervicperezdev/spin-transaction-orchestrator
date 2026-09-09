variable "name" { type = string }
variable "vpc_cidr" { type = string }
variable "availability_zones" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "database_subnet_cidrs" { type = list(string) }

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = var.name }
}

resource "aws_subnet" "private" {
  for_each          = { for index, cidr in var.private_subnet_cidrs : index => cidr }
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = var.availability_zones[each.key]
  tags              = { Name = "${var.name}-private-${each.key}", Tier = "application" }
}

resource "aws_subnet" "database" {
  for_each          = { for index, cidr in var.database_subnet_cidrs : index => cidr }
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = var.availability_zones[each.key]
  tags              = { Name = "${var.name}-database-${each.key}", Tier = "database" }
}

output "vpc_id" { value = aws_vpc.this.id }
output "private_subnet_ids" { value = values(aws_subnet.private)[*].id }
output "database_subnet_ids" { value = values(aws_subnet.database)[*].id }
