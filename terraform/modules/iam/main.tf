variable "role_name" { type = string }
variable "secret_resource_arns" { type = set(string) }

# Trust policy is intentionally not created: its OIDC issuer and service-account
# subject are cluster-specific inputs that must be reviewed with IRSA enablement.
resource "aws_iam_role" "workload" {
  name               = var.role_name
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Deny", Principal = "*", Action = "sts:AssumeRole" }] })
}

data "aws_iam_policy_document" "secrets" {
  count = length(var.secret_resource_arns) > 0 ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
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
