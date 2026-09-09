variable "cluster_name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "hosted_zone_arn" { type = string }
variable "hosted_zone_name" { type = string }

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = var.cluster_name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_iam_role" "load_balancer_controller" {
  name               = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# The controller's API surface is AWS-managed infrastructure rather than app
# data. Tag conditions bind create operations to controller-owned resources.
data "aws_iam_policy_document" "load_balancer_controller" {
  statement {
    effect = "Allow"
    actions = [
      "acm:DescribeCertificate", "acm:ListCertificates", "cognito-idp:DescribeUserPoolClient",
      "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses", "ec2:DescribeAvailabilityZones",
      "ec2:DescribeCoipPools", "ec2:DescribeInstances", "ec2:DescribeInternetGateways",
      "ec2:DescribeNetworkInterfaces", "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets",
      "ec2:DescribeTags", "ec2:DescribeVpcPeeringConnections", "ec2:DescribeVpcs",
      "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners", "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies", "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth", "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores", "elasticloadbalancing:DescribeListenerAttributes",
      "iam:ListServerCertificates", "iam:GetServerCertificate", "waf-regional:GetWebACLForResource",
      "waf-regional:GetWebACL", "waf-regional:AssociateWebACL", "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL", "wafv2:GetWebACLForResource", "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState", "shield:DescribeProtection", "shield:CreateProtection", "shield:DeleteProtection",
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup", "ec2:CreateTags", "ec2:DeleteTags", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
      "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener", "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteLoadBalancer", "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeleteListener", "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyRule", "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups", "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "load_balancer_controller" {
  name   = "manage-load-balancers"
  role   = aws_iam_role.load_balancer_controller.id
  policy = data.aws_iam_policy_document.load_balancer_controller.json
}

resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.load_balancer_controller.arn
  depends_on      = [aws_eks_addon.pod_identity_agent]
}

resource "helm_release" "load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = "1.11.0"
  namespace        = "kube-system"
  create_namespace = false
  upgrade_install  = true
  set = [
    { name = "clusterName", value = var.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = var.vpc_id },
    { name = "serviceAccount.create", value = "true" },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
  ]
  depends_on = [aws_eks_pod_identity_association.load_balancer_controller]
}

resource "aws_iam_role" "external_dns" {
  name               = "${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

data "aws_iam_policy_document" "external_dns" {
  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [var.hosted_zone_arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones", "route53:ListHostedZonesByName",
      "route53:ListResourceRecordSets",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "external_dns" {
  name   = "manage-approved-zone"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
  depends_on      = [aws_eks_addon.pod_identity_agent]
}

resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = "1.15.0"
  namespace        = "kube-system"
  create_namespace = false
  upgrade_install  = true
  set = [
    { name = "provider.name", value = "aws" },
    { name = "sources[0]", value = "ingress" },
    { name = "policy", value = "sync" },
    { name = "domainFilters[0]", value = var.hosted_zone_name },
    { name = "serviceAccount.create", value = "true" },
    { name = "serviceAccount.name", value = "external-dns" },
  ]
  depends_on = [aws_eks_pod_identity_association.external_dns]
}

output "load_balancer_controller_role_arn" { value = aws_iam_role.load_balancer_controller.arn }
output "external_dns_role_arn" { value = aws_iam_role.external_dns.arn }
