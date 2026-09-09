locals {
  name = "${var.project}-${var.environment}"
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source                = "../../modules/vpc"
  name                  = local.name
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
}

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = var.project
}

module "eks" {
  source                      = "../../modules/eks"
  cluster_name                = local.name
  subnet_ids                  = module.vpc.private_subnet_ids
  allowed_control_plane_cidrs = var.allowed_control_plane_cidrs
}

module "rds" {
  source                    = "../../modules/rds"
  identifier                = local.name
  database_name             = "transactions"
  subnet_ids                = module.vpc.database_subnet_ids
  vpc_id                    = module.vpc.vpc_id
  allowed_security_group_id = module.eks.node_security_group_id
}

module "workload_iam" {
  source               = "../../modules/iam"
  role_name            = "${local.name}-transaction-api"
  secret_resource_arns = var.workload_secret_arns
}
