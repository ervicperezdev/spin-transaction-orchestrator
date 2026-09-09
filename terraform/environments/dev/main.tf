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
  source                     = "../../modules/iam"
  role_name                  = "${local.name}-external-secrets"
  secret_resource_arns       = var.workload_secret_arns
  github_repository          = var.github_repository
  github_ref                 = var.github_ref
  ecr_repository_arn         = module.ecr.repository_arn
  eks_cluster_arn            = module.eks.cluster_arn
  eks_oidc_provider_arn      = var.eks_oidc_provider_arn
  eks_oidc_issuer_hostpath   = var.eks_oidc_issuer_hostpath
  kubernetes_namespace       = var.external_secrets_namespace
  kubernetes_service_account = var.external_secrets_service_account
}
