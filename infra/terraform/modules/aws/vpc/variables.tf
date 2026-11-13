variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}
variable "cluster_name" {
  description = "Karpenter 서브넷 탐색 태그(karpenter.sh/discovery)에 쓸 EKS 클러스터 이름"
  type        = string
}
variable "cidr" {
  description = "VPC CIDR (network-design.md 고정값)"
  type        = string
}
variable "azs" {
  description = "가용 영역 목록"
  type        = list(string)
}
variable "public_subnets" {
  description = "Public 서브넷 CIDR (ALB, NAT)"
  type        = list(string)
}
variable "app_subnets" {
  description = "Private-App 서브넷 CIDR (EKS 노드/파드)"
  type        = list(string)
}
variable "data_subnets" {
  description = "Private-Data 서브넷 CIDR (RDS, Redis, MSK)"
  type        = list(string)
}
variable "single_nat_gateway" {
  description = "true 면 NAT GW 1개 (학습 환경 비용 절감)"
  type        = bool
  default     = true
}
variable "enable_interface_endpoints" {
  description = "ECR/STS/Secrets Manager/Logs Interface Endpoint 생성 여부 (S3 Gateway 는 항상 생성)"
  type        = bool
  default     = true
}
variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
