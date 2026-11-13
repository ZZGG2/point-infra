# ECR 리포지토리(monolith, event-service): 푸시 시 스캔, 불변 태그, 수명주기 정책
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = each.key
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "KMS" }
  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "최근 ${var.keep_images}개 이미지만 보관"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.keep_images }
      action       = { type = "expire" }
    }]
  })
}
