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
  description = "GitHub owner/repository trusted to assume the deployment role."
  default     = "ervicperezdev/spin-transaction-orchestrator"
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
