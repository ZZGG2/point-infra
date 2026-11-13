output "web_url" {
  description = "서비스 접속 주소 (CloudFront)"
  value       = "https://${module.edge.cloudfront_domain}"
}
output "alb_url" {
  description = "ALB 직접 접근 (admin_cidrs 에서만, CloudFront 우회 확인용)"
  value       = "http://${data.aws_lb.api.dns_name}"
}
output "web_bucket" { value = module.edge.web_bucket }
output "cloudfront_distribution_id" { value = module.edge.cloudfront_distribution_id }
output "ecr_repository_urls" { value = module.ecr.repository_urls }
output "vpc_id" { value = module.vpc.vpc_id }
output "eks_cluster_name" { value = module.eks.cluster_name }
output "aurora_endpoint" { value = module.aurora.endpoint }
output "redis_endpoint" { value = module.elasticache.primary_endpoint }
output "msk_bootstrap_brokers_tls" { value = module.msk.bootstrap_brokers_tls }
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
output "argocd_ui_command" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8443:80  # 초기 비밀번호: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'"
}
