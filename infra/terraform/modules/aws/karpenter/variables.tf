variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}
variable "cluster_endpoint" {
  description = "EKS API 엔드포인트"
  type        = string
}
variable "chart_version" {
  description = "Karpenter Helm 차트 버전"
  type        = string
  default     = "1.15.1"
}
variable "replicas" {
  description = "컨트롤러 레플리카 수 (학습 환경 1, 운영 2)"
  type        = number
  default     = 1
}
variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
