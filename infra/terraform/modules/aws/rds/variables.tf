variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}
variable "db_subnet_group" {
  description = "DB 서브넷 그룹 (Private-Data)"
  type        = string
}
variable "allowed_security_group_ids" {
  description = "5432 접근 허용 SG (EKS 노드, MSK Connect)"
  type        = list(string)
}
variable "engine_version" {
  description = "PostgreSQL 메이저 버전 (ADR-0006: 16 고정, 마이너는 자동 업그레이드)"
  type        = string
  default     = "16"
}
variable "instance_class" {
  description = "인스턴스 클래스"
  type        = string
  default     = "db.t4g.small"
}
variable "multi_az" {
  description = "Multi-AZ (Standby 자동 장애 조치)"
  type        = bool
  default     = true
}
variable "allocated_storage" {
  description = "초기 스토리지 GiB"
  type        = number
  default     = 20
}
variable "max_allocated_storage" {
  description = "스토리지 자동 확장 상한 GiB"
  type        = number
  default     = 100
}
variable "deletion_protection" {
  description = "삭제 보호 (학습 환경 false → destroy 시 최종 스냅샷 생략)"
  type        = bool
  default     = false
}
variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
