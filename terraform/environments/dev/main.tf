locals {
  name         = "${var.project}-${var.environment}"
  cluster_name = "${var.project}-cluster"
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
  public_subnet_cidrs   = var.public_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
}

module "edge" {
  source                 = "../../modules/edge"
  name                   = local.name
  zone_name              = var.route53_zone_name
  hostname               = var.application_hostname
  vpc_id                 = module.vpc.vpc_id
  node_security_group_id = module.eks.node_security_group_id
}

module "addons" {
  source           = "../../modules/addons"
  cluster_name     = module.eks.cluster_name
  region           = var.aws_region
  vpc_id           = module.vpc.vpc_id
  hosted_zone_arn  = "arn:aws:route53:::hostedzone/${module.edge.zone_id}"
  hosted_zone_name = var.route53_zone_name
}

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = var.repository_name
}

module "eks" {
  source                      = "../../modules/eks"
  cluster_name                = local.cluster_name
  vpc_id                      = module.vpc.vpc_id
  subnet_ids                  = module.vpc.private_subnet_ids
  allowed_control_plane_cidrs = var.allowed_control_plane_cidrs
  github_deploy_role_arn      = module.workload_iam.github_deploy_role_arn
  terraform_apply_role_arn    = module.workload_iam.github_terraform_apply_role_arn
  cluster_admin_principal_arn = var.cluster_admin_principal_arn
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
  source                              = "../../modules/iam"
  role_name                           = "${local.name}-transaction-api"
  secret_resource_arns                = var.workload_secret_arns
  github_repository                   = var.github_repository
  github_ref                          = var.github_ref
  terraform_state_bucket_name         = var.terraform_state_bucket_name
  terraform_state_key                 = var.terraform_state_key
  terraform_apply_managed_policy_arns = var.terraform_apply_managed_policy_arns
  ecr_repository_arn                  = module.ecr.repository_arn
  eks_cluster_arn                     = module.eks.cluster_arn
  eks_oidc_provider_arn               = var.eks_oidc_provider_arn
  eks_oidc_issuer_hostpath            = var.eks_oidc_issuer_hostpath
  kubernetes_namespace                = var.application_namespace
  kubernetes_service_account          = var.application_service_account
}
