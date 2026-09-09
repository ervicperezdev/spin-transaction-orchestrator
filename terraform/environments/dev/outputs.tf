output "ecr_repository_url" { value = module.ecr.repository_url }
output "eks_cluster_name" { value = module.eks.cluster_name }
output "rds_endpoint" { value = module.rds.endpoint }
output "workload_role_arn" { value = module.workload_iam.role_arn }
output "github_deploy_role_arn" { value = module.workload_iam.github_deploy_role_arn }
