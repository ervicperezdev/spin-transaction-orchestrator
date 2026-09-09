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
}

variable "allowed_control_plane_cidrs" {
  type = list(string)
  validation {
    condition     = length(var.allowed_control_plane_cidrs) > 0 && !contains(var.allowed_control_plane_cidrs, "0.0.0.0/0")
    error_message = "Provide approved, non-public control-plane CIDRs."
  }
}
