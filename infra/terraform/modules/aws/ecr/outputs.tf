output "repository_urls" {
  description = "이름 → 리포지토리 URL"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
