variable "repository_name" { type = string }
variable "force_delete" {
  type        = bool
  description = "Whether Terraform may delete all images when deleting this repository. Keep false unless an approved ephemeral teardown accepts image loss."
  default     = false
}

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration { scan_on_push = true }
  # AWS-managed KMS key for ECR; no customer key material is exposed to CI.
  encryption_configuration { encryption_type = "KMS" }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = jsonencode({ rules = [{ rulePriority = 1, description = "Retain only recent untagged images", selection = { tagStatus = "untagged", countType = "imageCountMoreThan", countNumber = 10 }, action = { type = "expire" } }] })
}

output "repository_url" { value = aws_ecr_repository.this.repository_url }
output "repository_arn" { value = aws_ecr_repository.this.arn }
