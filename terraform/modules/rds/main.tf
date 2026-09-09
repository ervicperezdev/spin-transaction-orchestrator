variable "identifier" { type = string }
variable "database_name" { type = string }
variable "subnet_ids" { type = list(string) }
variable "vpc_id" { type = string }
variable "allowed_security_group_id" { type = string }

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-database"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "database" {
  name        = "${var.identifier}-database"
  description = "PostgreSQL only from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.allowed_security_group_id]
  }
  # Database replies are stateful; it never initiates connections.
  egress = []
}

resource "aws_db_instance" "this" {
  identifier                      = var.identifier
  engine                          = "postgres"
  engine_version                  = "16"
  instance_class                  = "db.t4g.medium"
  allocated_storage               = 20
  max_allocated_storage           = 100
  storage_encrypted               = true
  backup_retention_period         = 7
  deletion_protection             = true
  publicly_accessible             = false
  multi_az                        = true
  db_name                         = var.database_name
  username                        = "REPLACE_AT_DEPLOYMENT"
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.database.id]
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.identifier}-final"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}

output "endpoint" { value = aws_db_instance.this.address }
