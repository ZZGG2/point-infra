output "cluster_arn" { value = aws_rds_cluster.this.arn }
output "endpoint" { value = aws_rds_cluster.this.endpoint }
output "reader_endpoint" { value = aws_rds_cluster.this.reader_endpoint }
output "master_secret_arn" { value = aws_rds_cluster.this.master_user_secret[0].secret_arn }
output "security_group_id" { value = aws_security_group.aurora.id }
output "app_username" {
  description = "앱 전용 계정 이름 (terraform_data.app_user 완료 후 사용 가능)"
  value       = "app_rw"
  depends_on  = [terraform_data.app_user]
}
output "app_password" {
  value     = random_password.app.result
  sensitive = true
}
