output "web_url" {
  description = "서비스 접속 주소 (Gateway ALB, alb_ingress_cidrs 에서만 접근 가능 — 도메인·ACM 전까지)"
  value       = "http://${data.aws_lb.gateway.dns_name}"
}
output "ecr_repository_urls" { value = module.ecr.repository_urls }
output "vpc_id" { value = module.vpc.vpc_id }
output "eks_cluster_name" { value = module.eks.cluster_name }
output "rds_endpoint" { value = module.rds.address }
output "redis_endpoint" { value = module.elasticache.primary_endpoint }
output "msk_bootstrap_brokers_tls" { value = module.msk.bootstrap_brokers_tls }
output "waf_arn" { value = module.waf.web_acl_arn }
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
output "argocd_ui_command" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8443:80  # 초기 비밀번호: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'"
}
