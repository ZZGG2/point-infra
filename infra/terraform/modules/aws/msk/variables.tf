variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}
variable "subnet_ids" {
  description = "브로커 서브넷 (Private-Data). 브로커 수는 서브넷(AZ) 수의 배수"
  type        = list(string)
}
variable "allowed_security_group_ids" {
  description = "Kafka 접근 허용 SG (EKS 노드, MSK Connect)"
  type        = list(string)
}
variable "kafka_version" {
  description = "Kafka 버전 (MSK 지원 목록 참조)"
  type        = string
  default     = "3.9.x"
}
variable "broker_count" {
  description = "브로커 수"
  type        = number
  default     = 3
}
variable "instance_type" {
  description = "브로커 인스턴스 타입"
  type        = string
  default     = "kafka.t3.small"
}
variable "volume_size" {
  description = "브로커당 EBS GiB"
  type        = number
  default     = 20
}
variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
