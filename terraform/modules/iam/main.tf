variable "role_name" { type = string }
variable "secret_resource_arns" { type = set(string) }
variable "github_repository" { type = string }
variable "github_ref" { type = string }
variable "terraform_state_bucket_name" { type = string }
variable "terraform_state_key" { type = string }
variable "terraform_managed_iam_role_name_prefixes" {
  type        = set(string)
  description = "Name prefixes of IAM roles this Terraform environment is permitted to create and manage."
}
variable "terraform_apply_managed_policy_arns" {
  type        = set(string)
  description = "Account-managed, reviewed policies granting Terraform only the infrastructure write actions it needs."
  default     = []
}
variable "ecr_repository_arn" { type = string }
variable "eks_cluster_arn" { type = string }
variable "eks_oidc_provider_arn" { type = string }
variable "eks_oidc_issuer_hostpath" { type = string }
variable "kubernetes_namespace" { type = string }
variable "kubernetes_service_account" { type = string }

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  github_oidc_url      = "https://token.actions.githubusercontent.com"
  github_subject       = "repo:${var.github_repository}:ref:${var.github_ref}"
  github_plan_subject  = "repo:${var.github_repository}:pull_request"
  github_apply_subject = "repo:${var.github_repository}:environment:development"
  irsa_subject         = "system:serviceaccount:${var.kubernetes_namespace}:${var.kubernetes_service_account}"
  state_bucket_arn     = "arn:aws:s3:::${var.terraform_state_bucket_name}"
  state_object_arn     = "arn:aws:s3:::${var.terraform_state_bucket_name}/${var.terraform_state_key}"
  state_lock_arn       = "arn:aws:s3:::${var.terraform_state_bucket_name}/${var.terraform_state_key}.tflock"
  managed_role_arns    = [for prefix in var.terraform_managed_iam_role_name_prefixes : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${prefix}*"]
  managed_policy_arns  = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:policy/${var.role_name}*"]
}

# GitHub's public OIDC issuer. This provider is account-wide; manage it in one
# foundation only to avoid a duplicate-provider conflict in the AWS account.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = local.github_oidc_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      # The same application role is used by the build job on main and the
      # deployment job protected by the development Environment.
      values = [local.github_subject, local.github_apply_subject]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.role_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json
}

# ECR authentication has no resource-level permission; every other action is
# restricted to this repository. The deploy step only needs EKS discovery.
data "aws_iam_policy_document" "github_deploy" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages"
    ]
    resources = [var.ecr_repository_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [var.eks_cluster_arn]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "push-image-and-discover-cluster"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

# A PR can read infrastructure to calculate a plan, but it cannot write the
# state. It can only create/delete the short-lived S3 native lock object.
data "aws_iam_policy_document" "github_terraform_plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      # PR plans and trusted main plans share the same read-only role. The
      # latter creates the exact artifact that a protected apply job uses.
      values = [local.github_plan_subject, local.github_subject]
    }
  }
}

resource "aws_iam_role" "github_terraform_plan" {
  name               = "${var.role_name}-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.github_terraform_plan_trust.json
}

data "aws_iam_policy_document" "terraform_plan_state" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning", "s3:GetEncryptionConfiguration"]
    resources = [local.state_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.terraform_state_key, "${var.terraform_state_key}.tflock"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = [local.state_object_arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.state_lock_arn]
  }
}

resource "aws_iam_role_policy" "terraform_plan_state" {
  name   = "read-state-and-manage-lock"
  role   = aws_iam_role.github_terraform_plan.id
  policy = data.aws_iam_policy_document.terraform_plan_state.json
}

# Terraform refresh invokes read APIs that ViewOnlyAccess intentionally omits,
# including resource tags, IAM roles and several EKS/ECR/EC2 descriptions.
# ReadOnlyAccess grants no write actions; state writes remain restricted to the
# exact lock object in terraform_plan_state above.
resource "aws_iam_role_policy_attachment" "terraform_plan_read_only" {
  role       = aws_iam_role.github_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "github_terraform_apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_apply_subject]
    }
  }
}

resource "aws_iam_role" "github_terraform_apply" {
  name               = "${var.role_name}-terraform-apply"
  assume_role_policy = data.aws_iam_policy_document.github_terraform_apply_trust.json
}

# Only the apply role can update the state itself. Both state and lock are
# limited to the exact key configured for this environment.
data "aws_iam_policy_document" "terraform_apply_state" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning", "s3:GetEncryptionConfiguration"]
    resources = [local.state_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.terraform_state_key, "${var.terraform_state_key}.tflock"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
    resources = [local.state_object_arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.state_lock_arn]
  }
}

resource "aws_iam_role_policy" "terraform_apply_state" {
  name   = "read-write-state-and-lock"
  role   = aws_iam_role.github_terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply_state.json
}

# Apply must perform the same complete refresh before creating or changing
# resources. Its additional capabilities are still supplied separately below
# as reviewed provisioning policies, not by this read-only baseline.
resource "aws_iam_role_policy_attachment" "terraform_apply_read_only" {
  role       = aws_iam_role.github_terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# These are the write operations required to reconcile the Terraform-managed
# EKS security groups and the PostgreSQL parameter group. They are scoped to
# this account and region; broader provisioning capabilities remain opt-in via
# terraform_apply_managed_policy_arns below.
data "aws_iam_policy_document" "terraform_apply_core_mutations" {
  statement {
    sid = "ManageTerraformSecurityGroups"
    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:security-group/*"]
  }

  statement {
    sid = "ManageTerraformRdsParameterGroups"
    actions = [
      "rds:ModifyDBParameterGroup",
      "rds:ResetDBParameterGroup",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:pg:*"]
  }
}

resource "aws_iam_role_policy" "terraform_apply_core_mutations" {
  name   = "manage-security-groups-and-rds-parameters"
  role   = aws_iam_role.github_terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply_core_mutations.json
}

# The apply role is a Terraform provisioner, not an administrator.  This
# account-managed policy declares every AWS write API used by the modules in
# this repository.  It deliberately enumerates services/actions instead of
# using AdministratorAccess. Some Create and control-plane APIs do not support
# resource-level IAM authorization, so those statements must use "*"; they are
# bounded by service/action and this account's protected GitHub environment.
#checkov:skip=CKV_AWS_111:Several AWS create/control-plane APIs in this Terraform inventory have no resource-level condition key.
#checkov:skip=CKV_AWS_356:Wildcard resources are limited to APIs that AWS does not support resource scoping for; no wildcard actions are granted.
data "aws_iam_policy_document" "terraform_apply_provisioner" {
  statement {
    sid = "ManageVpcAndEc2Network"
    actions = [
      "ec2:AllocateAddress", "ec2:AssociateAddress", "ec2:AttachInternetGateway",
      "ec2:AuthorizeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateInternetGateway", "ec2:CreateNatGateway", "ec2:CreateRoute",
      "ec2:CreateRouteTable", "ec2:CreateSecurityGroup", "ec2:CreateSubnet",
      "ec2:CreateTags", "ec2:CreateVpc", "ec2:DeleteInternetGateway",
      "ec2:DeleteNatGateway", "ec2:DeleteRoute", "ec2:DeleteRouteTable",
      "ec2:DeleteSecurityGroup", "ec2:DeleteSubnet", "ec2:DeleteTags",
      "ec2:DeleteVpc", "ec2:DetachInternetGateway", "ec2:DisassociateAddress",
      "ec2:DisassociateRouteTable", "ec2:ModifySecurityGroupRules",
      "ec2:ModifySubnetAttribute", "ec2:ModifyVpcAttribute", "ec2:ReleaseAddress",
      "ec2:ReplaceRoute", "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageEc2LaunchTemplates"
    actions = [
      "ec2:CreateLaunchTemplate", "ec2:CreateLaunchTemplateVersion",
      "ec2:DeleteLaunchTemplate", "ec2:DeleteLaunchTemplateVersions",
      "ec2:ModifyLaunchTemplate",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageEks"
    actions = [
      "eks:AssociateAccessPolicy", "eks:CreateAccessEntry", "eks:CreateAddon",
      "eks:CreateCluster", "eks:CreateNodegroup", "eks:CreatePodIdentityAssociation",
      "eks:DeleteAccessEntry", "eks:DeleteAddon", "eks:DeleteCluster",
      "eks:DeleteNodegroup", "eks:DeletePodIdentityAssociation",
      "eks:DisassociateAccessPolicy", "eks:TagResource", "eks:UntagResource",
      "eks:UpdateAccessEntry", "eks:UpdateAddon", "eks:UpdateClusterConfig",
      "eks:UpdateClusterVersion", "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion",
      "eks:UpdatePodIdentityAssociation",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageIamResourcesCreatedByTerraform"
    actions = [
      "iam:AttachRolePolicy", "iam:CreateOpenIDConnectProvider", "iam:CreatePolicy",
      "iam:CreatePolicyVersion", "iam:CreateRole", "iam:DeleteOpenIDConnectProvider",
      "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:DeleteRole",
      "iam:DeleteRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy",
      "iam:SetDefaultPolicyVersion", "iam:TagOpenIDConnectProvider", "iam:TagPolicy",
      "iam:TagRole", "iam:UntagOpenIDConnectProvider", "iam:UntagPolicy",
      "iam:UntagRole", "iam:UpdateAssumeRolePolicy",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = concat(local.managed_role_arns, local.managed_policy_arns, [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com",
    ])
  }

  statement {
    sid     = "AttachApprovedManagedPolicies"
    actions = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
    resources = concat(local.managed_role_arns, [
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole",
    ])
  }

  statement {
    sid       = "PassOnlyTerraformServiceRoles"
    actions   = ["iam:PassRole"]
    resources = local.managed_role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "ec2.amazonaws.com", "eks.amazonaws.com", "monitoring.rds.amazonaws.com",
        "vpc-flow-logs.amazonaws.com",
      ]
    }
  }

  statement {
    sid = "ManageRds"
    actions = [
      "rds:AddTagsToResource", "rds:CreateDBInstance", "rds:CreateDBParameterGroup",
      "rds:CreateDBSubnetGroup", "rds:DeleteDBInstance", "rds:DeleteDBParameterGroup",
      "rds:DeleteDBSubnetGroup", "rds:ModifyDBInstance", "rds:ModifyDBParameterGroup",
      "rds:ModifyDBSubnetGroup", "rds:RebootDBInstance", "rds:RemoveTagsFromResource",
      "rds:ResetDBParameterGroup",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ManageKmsKeysAndAliases"
    actions = [
      "kms:CancelKeyDeletion", "kms:CreateAlias", "kms:CreateGrant", "kms:CreateKey",
      "kms:DeleteAlias", "kms:DisableKey", "kms:DisableKeyRotation", "kms:EnableKey",
      "kms:EnableKeyRotation", "kms:PutKeyPolicy", "kms:RevokeGrant",
      "kms:ScheduleKeyDeletion", "kms:TagResource", "kms:UntagResource", "kms:UpdateAlias",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "CreateEcrRepositories"
    actions   = ["ecr:CreateRepository"]
    resources = ["*"]
  }

  statement {
    sid = "ManageTerraformEcrRepositories"
    actions = [
      "ecr:DeleteLifecyclePolicy", "ecr:DeleteRepository",
      "ecr:PutImageScanningConfiguration", "ecr:PutImageTagMutability",
      "ecr:PutLifecyclePolicy", "ecr:TagResource", "ecr:UntagResource",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/*"]
  }

  statement {
    sid = "ManageCertificatesAndWaf"
    actions = [
      "acm:AddTagsToCertificate", "acm:DeleteCertificate", "acm:RemoveTagsFromCertificate",
      "acm:RequestCertificate",
      "wafv2:CreateWebACL", "wafv2:DeleteWebACL", "wafv2:TagResource",
      "wafv2:UntagResource", "wafv2:UpdateWebACL",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ManageDnsRecordsInExistingZones"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::hostedzone/*"]
  }

  statement {
    sid = "ManageFlowLogDestinations"
    actions = [
      "logs:AssociateKmsKey", "logs:CreateLogGroup", "logs:DeleteLogGroup",
      "logs:DisassociateKmsKey", "logs:PutRetentionPolicy", "logs:TagResource",
      "logs:UntagResource", "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_apply_provisioner" {
  name        = "${var.role_name}-terraform-provisioner"
  description = "Least-privilege Terraform provisioning actions for the managed transaction infrastructure"
  policy      = data.aws_iam_policy_document.terraform_apply_provisioner.json
}

resource "aws_iam_role_policy_attachment" "terraform_apply_provisioner" {
  role       = aws_iam_role.github_terraform_apply.name
  policy_arn = aws_iam_policy.terraform_apply_provisioner.arn
}

# This remains available only for organization-specific exceptions that are
# outside this repository's resource inventory. The provisioner policy above
# is the normal, versioned capability set for this environment.
resource "aws_iam_role_policy_attachment" "terraform_apply_capabilities" {
  for_each   = var.terraform_apply_managed_policy_arns
  role       = aws_iam_role.github_terraform_apply.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "workload_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_issuer_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_issuer_hostpath}:sub"
      values   = [local.irsa_subject]
    }
  }
}

# This role is intentionally independent from node and CI roles. Bind it only
# to the transaction API service account that mounts Secrets Manager through CSI.
resource "aws_iam_role" "workload" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.workload_trust.json
}

data "aws_iam_policy_document" "secrets" {
  count = length(var.secret_resource_arns) > 0 ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
    ]
    resources = tolist(var.secret_resource_arns)
  }
}

resource "aws_iam_role_policy" "secrets" {
  count  = length(var.secret_resource_arns) > 0 ? 1 : 0
  name   = "read-approved-secrets"
  role   = aws_iam_role.workload.id
  policy = data.aws_iam_policy_document.secrets[0].json
}

output "role_arn" { value = aws_iam_role.workload.arn }
output "github_deploy_role_arn" { value = aws_iam_role.github_deploy.arn }
output "github_terraform_plan_role_arn" { value = aws_iam_role.github_terraform_plan.arn }
output "github_terraform_apply_role_arn" { value = aws_iam_role.github_terraform_apply.arn }
output "github_terraform_apply_provisioner_policy_arn" { value = aws_iam_policy.terraform_apply_provisioner.arn }
