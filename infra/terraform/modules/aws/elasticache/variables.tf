variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}
variable "subnet_ids" {
  description = "Private-Data 서브넷"
  type        = list(string)
}
variable "allowed_security_group_ids" {
  description = "6379 접근 허용 SG (EKS 노드)"
  type        = list(string)
}
variable "engine_version" {
  description = "Valkey 엔진 버전"
  type        = string
  default     = "7.2"
}
variable "node_type" {
  description = "노드 타입"
  type        = string
  default     = "cache.t4g.small"
}
variable "replicas" {
  description = "Replica 수 (0 이면 Multi-AZ 비활성)"
  type        = number
  default     = 1
}
variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
