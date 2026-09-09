variable "aws_region" { type = string }
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
variable "database_subnet_cidrs" { type = list(string) }
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
  description = "GitHub owner/repository trusted to assume the deployment role."
  default     = "ervicperezdev/spin-transaction-orchestrator"
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

variable "external_secrets_namespace" {
  type    = string
  default = "external-secrets"
}

variable "external_secrets_service_account" {
  type    = string
  default = "external-secrets"
}

variable "allowed_control_plane_cidrs" {
  type = list(string)
  validation {
    condition     = length(var.allowed_control_plane_cidrs) > 0 && !contains(var.allowed_control_plane_cidrs, "0.0.0.0/0")
    error_message = "Provide approved, non-public control-plane CIDRs."
  }
}
