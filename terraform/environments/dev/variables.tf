variable "aws_region" { type = string }
variable "cluster_admin_principal_arn" {
  type        = string
  description = "IAM principal that administers the development EKS cluster."
  default     = "arn:aws:iam::911167887101:user/ervicperezdevpro"
}
variable "project" {
  type    = string
  default = "spin-transaction-orchestrator"
}
variable "environment" {
  type    = string
  default = "dev"
}
variable "vpc_cidr" { type = string }
variable "availability_zones" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "database_subnet_cidrs" { type = list(string) }
variable "route53_zone_name" { type = string }
variable "application_hostname" { type = string }
variable "workload_secret_arns" {
  type    = set(string)
  default = []

  validation {
    condition     = alltrue([for arn in var.workload_secret_arns : can(regex("^arn:[^:]+:secretsmanager:[^:]+:[0-9]{12}:secret:", arn))])
    error_message = "workload_secret_arns must contain exact AWS Secrets Manager ARNs. Wildcards are not permitted."
  }
}

variable "github_repository" {
  type        = string
  description = "GitHub OIDC repository subject prefix configured for this repository."
  default     = "ervicperezdev@55267476/spin-transaction-orchestrator@1360862265"
}

variable "repository_name" {
  type        = string
  description = "GitHub owner/repository trusted to assume the deployment role."
  default     = "spin-transaction-orchestrator"
}


variable "github_ref" {
  type        = string
  description = "Fully-qualified Git ref trusted to deploy."
  default     = "refs/heads/main"

  validation {
    condition     = can(regex("^refs/heads/", var.github_ref))
    error_message = "github_ref must be a branch ref (for example refs/heads/main)."
  }
}

variable "terraform_state_bucket_name" {
  type        = string
  description = "Pre-created S3 bucket that holds the development Terraform state."
  default     = "spin-transaction-state"
}

variable "terraform_state_key" {
  type        = string
  description = "Exact S3 state key; IAM permissions include only this object and its native S3 lock."
  default     = "spin-transaction-orchestrator/dev/terraform.tfstate"
}

variable "terraform_apply_managed_policy_arns" {
  type        = set(string)
  description = "Reviewed account-managed policies with write permissions for the Terraform-managed development infrastructure."
  default     = []
}

variable "eks_oidc_provider_arn" {
  type        = string
  description = "Pre-created IAM OIDC provider ARN for the EKS cluster issuer."
}

variable "eks_oidc_issuer_hostpath" {
  type        = string
  description = "EKS issuer without https://, used in IRSA condition keys."

  validation {
    condition     = !startswith(var.eks_oidc_issuer_hostpath, "https://")
    error_message = "eks_oidc_issuer_hostpath must omit https://."
  }
}

variable "application_namespace" {
  type    = string
  default = "transaction-api"
}

variable "application_service_account" {
  type    = string
  default = "transaction-api"
}

variable "allowed_control_plane_cidrs" {
  type = list(string)
  validation {
    condition     = length(var.allowed_control_plane_cidrs) > 0 && !contains(var.allowed_control_plane_cidrs, "0.0.0.0/1")
    error_message = "Provide approved, non-public control-plane CIDRs."
  }
}

# Perfil FinOps explícito para dev. Los valores por defecto de los módulos
# permanecen orientados a producción; este entorno opta por capacidad mínima.
variable "enable_waf" {
  type        = bool
  description = "Create the regional WAF ACL. Disabled by default only for dev."
  default     = false
}
variable "node_instance_types" {
  type        = list(string)
  description = "Development base-node type. t3.medium is intentionally explicit; production declares its own profile."
  default     = ["t3.medium"]

  validation {
    condition     = length(var.node_instance_types) == 1 && var.node_instance_types[0] == "t3.medium"
    error_message = "The approved development base profile uses exactly one t3.medium instance type."
  }
}
variable "node_min_size" {
  type        = number
  description = "Development baseline: one ON_DEMAND node. This profile is not highly available."
  default     = 1

  validation {
    condition     = var.node_min_size == 1
    error_message = "The approved development profile keeps one base node; change the reviewed profile before increasing its minimum."
  }
}
variable "node_desired_size" {
  type        = number
  description = "Development baseline: one ON_DEMAND node; autoscaling may grow to node_max_size during a peak."
  default     = 1

  validation {
    condition     = var.node_desired_size == 1
    error_message = "The approved development profile starts with one desired node; use autoscaling up to the reviewed maximum for a peak."
  }
}
variable "node_max_size" {
  type        = number
  description = "Peak recovery ceiling for development. Spot is not configured for critical system components."
  default     = 2

  validation {
    condition     = var.node_max_size == 2
    error_message = "The approved development profile permits recovery to at most two nodes."
  }
}
variable "cluster_log_types" {
  type        = list(string)
  description = "Minimal EKS control-plane security evidence retained in dev."
  default     = ["api", "audit"]
}
variable "rds_instance_class" {
  type        = string
  description = "Development RDS size; production must choose its own profile."
  default     = "db.t4g.micro"
}
variable "rds_backup_retention_period" {
  type    = number
  default = 1
}
variable "rds_deletion_protection" {
  type    = bool
  default = false
}
variable "rds_multi_az" {
  type    = bool
  default = false
}
variable "rds_enabled_cloudwatch_logs_exports" {
  type        = list(string)
  description = "CloudWatch PostgreSQL log exports; disabled in dev to reduce ingestion."
  default     = []
}
