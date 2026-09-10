variable "role_name" { type = string }
variable "secret_resource_arns" { type = set(string) }
variable "github_repository" { type = string }
variable "github_ref" { type = string }
variable "terraform_state_bucket_name" { type = string }
variable "terraform_state_key" { type = string }
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

locals {
  github_oidc_url      = "https://token.actions.githubusercontent.com"
  github_subject       = "repo:${var.github_repository}:ref:${var.github_ref}"
  github_plan_subject  = "repo:${var.github_repository}:pull_request"
  github_apply_subject = "repo:${var.github_repository}:environment:development"
  irsa_subject         = "system:serviceaccount:${var.kubernetes_namespace}:${var.kubernetes_service_account}"
  state_bucket_arn     = "arn:aws:s3:::${var.terraform_state_bucket_name}"
  state_object_arn     = "arn:aws:s3:::${var.terraform_state_bucket_name}/${var.terraform_state_key}"
  state_lock_arn       = "arn:aws:s3:::${var.terraform_state_bucket_name}/${var.terraform_state_key}.tflock"
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
      values   = [local.github_plan_subject]
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

# ViewOnlyAccess supplies Describe/List/Get calls used by Terraform refreshes;
# mutations remain unavailable because this is not a write policy.
resource "aws_iam_role_policy_attachment" "terraform_plan_view_only" {
  role       = aws_iam_role.github_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
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

# Infrastructure write permissions are supplied as approved, account-managed
# policies rather than silently granting AdministratorAccess.
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
