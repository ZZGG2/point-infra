variable "repositories" {
  description = "생성할 리포지토리 이름"
  type        = list(string)
  default     = ["monolith", "event-service"]
}
variable "force_delete" {
  description = "이미지가 있어도 destroy 허용 (학습 환경 true)"
  type        = bool
  default     = true
}
variable "keep_images" {
  description = "리포지토리당 보관할 이미지 수"
  type        = number
  default     = 30
}
variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
