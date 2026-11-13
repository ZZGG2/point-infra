variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}
variable "alb_dns_name" {
  description = "API 오리진 ALB DNS (AWS Load Balancer Controller 가 Ingress 로 생성)"
  type        = string
}
variable "rate_limit_per_5min" {
  description = "IP 당 5분 요청 상한 (초과 시 WAF 차단)"
  type        = number
  default     = 2000
}
variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
