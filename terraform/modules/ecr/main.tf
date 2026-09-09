variable "repository_name" { type = string }

resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = jsonencode({ rules = [{ rulePriority = 1, description = "Retain only recent untagged images", selection = { tagStatus = "untagged", countType = "imageCountMoreThan", countNumber = 10 }, action = { type = "expire" } }] })
}

output "repository_url" { value = aws_ecr_repository.this.repository_url }
output "repository_arn" { value = aws_ecr_repository.this.arn }
