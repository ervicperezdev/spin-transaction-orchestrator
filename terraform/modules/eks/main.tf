variable "cluster_name" { type = string }
variable "subnet_ids" { type = list(string) }
variable "vpc_id" { type = string }
variable "github_deploy_role_arn" { type = string }
variable "terraform_apply_role_arn" {
  type        = string
  description = "OIDC Terraform apply role that manages EKS add-ons through the Kubernetes and Helm providers."
}
variable "terraform_plan_role_arn" {
  type        = string
  description = "OIDC Terraform plan role allowed to read Kubernetes resources during a PR refresh."
}
variable "cluster_admin_principal_arn" {
  type        = string
  description = "IAM principal allowed to administer the cluster and install platform addons."
}
variable "allowed_control_plane_cidrs" { type = list(string) }
variable "node_instance_types" {
  type        = list(string)
  description = "EC2 instance types permitted in the managed node group."
  default     = ["t3.medium"]
}
variable "node_min_size" {
  type        = number
  description = "Minimum managed node group size."
  default     = 2
}
variable "node_desired_size" {
  type        = number
  description = "Desired managed node group size."
  default     = 2
}
variable "node_max_size" {
  type        = number
  description = "Maximum managed node group size."
  default     = 4
}
variable "cluster_log_types" {
  type        = list(string)
  description = "EKS control-plane logs retained for this environment."
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  validation {
    condition     = contains(var.cluster_log_types, "api") && contains(var.cluster_log_types, "audit")
    error_message = "cluster_log_types must retain at least the api and audit EKS control-plane logs."
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "secrets_kms" {
  # checkov:skip=CKV_AWS_109: A customer-managed KMS key requires an account-root administration statement; encryption consumers receive only service grants.
  # checkov:skip=CKV_AWS_111: A customer-managed KMS key requires an account-root administration statement; encryption consumers receive only service grants.
  # checkov:skip=CKV_AWS_356: KMS key policies use Resource="*" by AWS design because the policy is attached to the key itself.
  statement {
    sid       = "AllowAccountAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_security_group" "node" {
  # checkov:skip=CKV_AWS_382: Nodes require controlled outbound HTTPS/DNS through NAT for EKS, image pulls and AWS APIs until VPC endpoints and NetworkPolicies are fully enforced.
  name        = "${var.cluster_name}-node"
  description = "EKS worker nodes; no public ingress"
  vpc_id      = var.vpc_id
  ingress {
    description = "Node-to-node and pod networking"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }
  egress {
    description = "Private subnet egress via NAT/VPC endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "cluster" {
  # checkov:skip=CKV_AWS_382: EKS control-plane managed traffic requires unrestricted return/outbound connectivity; ingress is limited to the node security group.
  name        = "${var.cluster_name}-cluster"
  description = "EKS API endpoint; accepts traffic only from worker nodes"
  vpc_id      = var.vpc_id
  ingress {
    description     = "Kubelet and pod API access"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.node.id]
  }
  egress {
    description = "EKS control-plane managed outbound and return traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "node_from_cluster_kubelet" {
  type                     = "ingress"
  description              = "Control plane to kubelet"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

# El Service del webhook expone 443 y lo dirige al puerto 9443 de los pods.
resource "aws_security_group_rule" "node_from_cluster_alb_webhook" {
  type                     = "ingress"
  description              = "EKS control plane to AWS Load Balancer Controller webhook"
  from_port                = 9443
  to_port                  = 9443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_launch_template" "node" {
  # checkov:skip=CKV_AWS_341: Hop limit 2 is required for supported EKS pod networking paths that access IMDS; IMDSv2 remains mandatory and instance metadata tags are disabled.
  name_prefix = "${var.cluster_name}-node-"
  # Managed node groups do not automatically inherit custom security groups
  # supplied to the EKS control-plane ENIs. Associate the EKS-managed cluster
  # security group explicitly so the API server can reach kubelet on TCP/10250
  # for logs, exec and port-forward, while the node SG remains the workload
  # boundary.
  vpc_security_group_ids = [
    aws_security_group.node.id,
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
  ]
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# EXC-001: temporary dev exception for GitHub-hosted runners.
# Expires: 2026-09-23. See docs/security/EXC-001-eks-public-endpoint.md.
# nosemgrep: terraform.lang.security.eks-public-endpoint-enabled.eks-public-endpoint-enabled
resource "aws_eks_cluster" "this" {
  # checkov:skip=CKV_AWS_39: EXC-001 authorizes a temporary, CIDR-restricted public endpoint for GitHub-hosted development runners; private endpoint stays enabled.
  # checkov:skip=CKV_AWS_37: Dev intentionally retains only api and audit under TRA-46; the module default preserves all EKS control-plane logs for other environments.
  # nosemgrep: terraform.lang.security.eks-insufficient-control-plane-logging.eks-insufficient-control-plane-logging
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = "1.31"

  access_config {

    authentication_mode = "API_AND_CONFIG_MAP"

  }
  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.allowed_control_plane_cidrs
  }

  # api and audit are enforced by cluster_log_types validation above. Semgrep
  # cannot infer variable validation through the module boundary.
  # nosemgrep: terraform.lang.security.eks-insufficient-control-plane-logging.eks-insufficient-control-plane-logging
  enabled_cluster_log_types = var.cluster_log_types

  encryption_config {
    resources = ["secrets"]
    provider { key_arn = aws_kms_key.secrets.arn }
  }
  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_kms_key" "secrets" {
  description             = "Envelope encryption for Kubernetes Secrets in ${var.cluster_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.secrets_kms.json
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "aws_eks_access_entry" "cluster_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.cluster_admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_admin" {
  cluster_name  = aws_eks_access_entry.cluster_admin.cluster_name
  principal_arn = aws_eks_access_entry.cluster_admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_entry" "github_deploy" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.github_deploy_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_deploy" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.github_deploy_role_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["transaction-api"]
  }

  depends_on = [
    aws_eks_access_entry.github_deploy
  ]
}

# Terraform manages cluster-scoped add-ons and a namespace; its separate OIDC
# apply role needs API access, but no application delivery role is elevated.
resource "aws_eks_access_entry" "terraform_apply" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.terraform_apply_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "terraform_apply" {
  cluster_name  = aws_eks_access_entry.terraform_apply.cluster_name
  principal_arn = aws_eks_access_entry.terraform_apply.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# A plan refreshes Kubernetes and Helm resources, but must not alter them. The
# EKS view policy deliberately excludes secret reads and provides no mutation.
resource "aws_eks_access_entry" "terraform_plan" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.terraform_plan_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "terraform_plan" {
  cluster_name  = aws_eks_access_entry.terraform_plan.cluster_name
  principal_arn = aws_eks_access_entry.terraform_plan.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  capacity_type   = "ON_DEMAND"
  instance_types  = var.node_instance_types
  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }
  # force_update_version lets EKS terminate nodes even when a PDB blocks pod
  # eviction; prevents PodEvictionFailure from stalling launch-template rollouts.
  force_update_version = true
  update_config { max_unavailable = 1 }
  depends_on = [aws_iam_role_policy_attachment.node_worker, aws_iam_role_policy_attachment.node_cni, aws_iam_role_policy_attachment.node_ecr]
}

output "cluster_name" { value = aws_eks_cluster.this.name }
output "cluster_arn" { value = aws_eks_cluster.this.arn }
output "cluster_endpoint" { value = aws_eks_cluster.this.endpoint }
output "cluster_ca_certificate" { value = aws_eks_cluster.this.certificate_authority[0].data }
output "cluster_security_group_id" { value = aws_security_group.cluster.id }
output "node_security_group_id" { value = aws_security_group.node.id }
