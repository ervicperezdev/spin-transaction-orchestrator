variable "role_name" { type = string }
variable "secret_resource_arns" { type = set(string) }
variable "github_repository" { type = string }
variable "github_ref" { type = string }
variable "ecr_repository_arn" { type = string }
variable "eks_cluster_arn" { type = string }
variable "eks_oidc_provider_arn" { type = string }
variable "eks_oidc_issuer_hostpath" { type = string }
variable "kubernetes_namespace" { type = string }
variable "kubernetes_service_account" { type = string }

locals {
  github_oidc_url = "https://token.actions.githubusercontent.com"
  github_subject  = "repo:${var.github_repository}:ref:${var.github_ref}"
  irsa_subject    = "system:serviceaccount:${var.kubernetes_namespace}:${var.kubernetes_service_account}"
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
      values   = [local.github_subject]
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
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
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
