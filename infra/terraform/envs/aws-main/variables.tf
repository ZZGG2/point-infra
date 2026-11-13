variable "single_nat_gateway" {
  description = "학습 환경 비용 절감용. 운영 환경은 false (AZ별 NAT)"
  type        = bool
  default     = true
}
