variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}
variable "alb_arn" {
  description = "WAF 를 연결할 ALB ARN (Gateway 로 생성된 ALB)"
  type        = string
}
variable "rate_limit_per_5min" {
  description = "IP 당 5분 요청 상한 (초과 시 차단)"
  type        = number
  default     = 2000
}
variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
