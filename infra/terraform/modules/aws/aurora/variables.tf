variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}
variable "region" {
  description = "AWS 리전 (Data API 호출용)"
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
  description = "Aurora PostgreSQL 16 엔진 버전 (ADR-0006)"
  type        = string
  default     = "16.15"
}
variable "instance_class" {
  description = "인스턴스 클래스 (Data API 사용 → db.serverless 또는 r/x 계열. t 계열 불가)"
  type        = string
  default     = "db.serverless"
}
variable "serverless_min_acu" {
  description = "Serverless v2 최소 ACU"
  type        = number
  default     = 0.5
}
variable "serverless_max_acu" {
  description = "Serverless v2 최대 ACU"
  type        = number
  default     = 4
}
variable "instance_count" {
  description = "인스턴스 수 (writer 1 + reader N)"
  type        = number
  default     = 2
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
