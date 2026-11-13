variable "region" {
  description = "AWS Main 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "single_nat_gateway" {
  description = "학습 환경 비용 절감용. 운영 환경은 false (AZ별 NAT)"
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "ECR/STS/Secrets Manager/Logs Interface Endpoint (3 AZ × 5개, 시간당 약 $0.2)"
  type        = bool
  default     = true
}

variable "admin_cidrs" {
  description = "EKS API·ALB 직접 접근 허용 CIDR. 비우면 terraform 실행 PC 의 공인 IP/32"
  type        = list(string)
  default     = []
}

variable "git_repo_url" {
  description = "ArgoCD 가 동기화할 GitOps 저장소"
  type        = string
  default     = "https://github.com/ZZGG2/point-infra.git"
}

variable "git_revision" {
  description = "ArgoCD 동기화 브랜치"
  type        = string
  default     = "main"
}

variable "apps_path" {
  description = "앱 kustomize 경로. k8s/overlays/aws-demo = 데모 사용자·이벤트 시드 포함 (검증용)"
  type        = string
  default     = "k8s/overlays/aws"
}

variable "image_tag" {
  description = "monolith / event-service 이미지 태그 (scripts/aws/build-push.ps1 이 푸시한 태그)"
  type        = string
  default     = "0.1.0"
}

variable "aurora_instance_count" {
  description = "Aurora 인스턴스 수 (writer 1 + reader N)"
  type        = number
  default     = 2
}

variable "msk_broker_count" {
  description = "MSK 브로커 수 (3 AZ → 3의 배수)"
  type        = number
  default     = 3
}

variable "alb_wait_minutes" {
  description = "ArgoCD 가 Ingress 를 동기화해 ALB 가 생길 때까지 기다리는 최대 시간"
  type        = number
  default     = 25
}
