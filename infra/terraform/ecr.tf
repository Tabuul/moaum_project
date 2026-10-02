# Immutable tags: an image tagged with a commit SHA can never be replaced, so a
# rollback to that SHA redeploys exactly what ran before, not a rebuild.
resource "aws_ecr_repository" "svc" {
  for_each             = toset(["api", "frontend"])
  name                 = "moaumpp/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "svc" {
  for_each   = aws_ecr_repository.svc
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last 30 images (30 rollback points)"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }
      action       = { type = "expire" }
    }]
  })
}
