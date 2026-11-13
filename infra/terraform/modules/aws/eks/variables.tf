variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}
variable "cluster_version" {
  description = "Kubernetes 버전 (표준 지원 기간 내 버전 사용 — 연장 지원은 시간당 요금 6배)"
  type        = string
  default     = "1.35"
}
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}
variable "subnet_ids" {
  description = "노드/컨트롤 플레인 ENI 서브넷 (Private-App)"
  type        = list(string)
}
variable "public_access_cidrs" {
  description = "API 서버 퍼블릭 엔드포인트 접근 허용 CIDR"
  type        = list(string)
}
variable "core_instance_types" {
  description = "core 노드 그룹 인스턴스 타입"
  type        = list(string)
  default     = ["t3.large"]
}
variable "core_min_size" {
  description = "core 노드 최소(=초기) 대수"
  type        = number
  default     = 2
}
variable "core_max_size" {
  description = "core 노드 최대 대수"
  type        = number
  default     = 4
}
variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
