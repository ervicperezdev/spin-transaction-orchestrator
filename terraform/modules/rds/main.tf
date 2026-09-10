variable "identifier" { type = string }
variable "database_name" { type = string }
variable "subnet_ids" { type = list(string) }
variable "vpc_id" { type = string }
variable "allowed_security_group_id" { type = string }
variable "instance_class" {
  type        = string
  description = "RDS instance class for this environment."
  default     = "db.t4g.medium"
}
variable "backup_retention_period" {
  type        = number
  description = "Number of days to retain automated backups."
  default     = 7
}
variable "deletion_protection" {
  type        = bool
  description = "Protect the database from accidental deletion."
  default     = true
}
variable "multi_az" {
  type        = bool
  description = "Create a standby instance in another Availability Zone."
  default     = true
}
variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "PostgreSQL log types exported to CloudWatch."
  default     = ["postgresql", "upgrade"]
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "performance_insights_kms" {
  # checkov:skip=CKV_AWS_109: A customer-managed KMS key requires an account-root administration statement; encryption consumers receive only service grants.
  # checkov:skip=CKV_AWS_111: A customer-managed KMS key requires an account-root administration statement; encryption consumers receive only service grants.
  # checkov:skip=CKV_AWS_356: KMS key policies use Resource="*" by AWS design because the policy is attached to the key itself.
  statement {
    sid       = "AllowAccountAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "performance_insights" {
  description             = "Performance Insights encryption for ${var.identifier}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.performance_insights_kms.json
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-database"
  subnet_ids = var.subnet_ids
}

data "aws_iam_policy_document" "enhanced_monitoring_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  name               = "${var.identifier}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_trust.json
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.identifier}-postgres16"
  family = "postgres16"

  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name  = "log_statement"
    value = "ddl"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
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
  # checkov:skip=CKV2_AWS_69: PostgreSQL TLS is enforced through the attached postgres16 parameter group (rds.force_ssl=1); this graph check does not follow parameter-group settings.
  identifier                          = var.identifier
  engine                              = "postgres"
  engine_version                      = "16"
  instance_class                      = var.instance_class
  allocated_storage                   = 20
  max_allocated_storage               = 100
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  backup_retention_period             = var.backup_retention_period
  deletion_protection                 = var.deletion_protection
  publicly_accessible                 = false
  multi_az                            = var.multi_az
  db_name                             = var.database_name
  username                            = "REPLACE_AT_DEPLOYMENT"
  manage_master_user_password         = true
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.database.id]
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.identifier}-final"
  enabled_cloudwatch_logs_exports     = var.enabled_cloudwatch_logs_exports
  copy_tags_to_snapshot               = true
  auto_minor_version_upgrade          = true
  performance_insights_enabled        = true
  performance_insights_kms_key_id     = aws_kms_key.performance_insights.arn
  monitoring_interval                 = 60
  monitoring_role_arn                 = aws_iam_role.enhanced_monitoring.arn
  parameter_group_name                = aws_db_parameter_group.postgres.name
  depends_on = [aws_iam_role_policy_attachment.enhanced_monitoring]
}

output "endpoint" { value = aws_db_instance.this.address }
