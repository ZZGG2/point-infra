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
  description = "ECR/STS/Secrets Manager/Logs Interface Endpoint (3 AZ x 5개, 시간당 약 $0.2 — 학습 환경 기본 끔, NAT 경유)"
  type        = bool
  default     = false
}

variable "admin_cidrs" {
  description = "EKS API·ALB 직접 접근 허용 CIDR. 비우면 terraform 실행 PC 의 공인 IP/32"
  type        = list(string)
  default     = []
}

variable "alb_ingress_cidrs" {
  description = "ALB(HTTP 80) 접근 허용 CIDR. 비우면 admin_cidrs. 도메인·ACM 후 HTTPS 공개 예정"
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

variable "web_image_tag" {
  description = "web(프론트엔드) 이미지 태그 (point-frontend 커밋 기준)"
  type        = string
  default     = "0.1.0"
}

variable "rds_instance_class" {
  description = "RDS PostgreSQL 인스턴스 클래스"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_multi_az" {
  description = "RDS Multi-AZ (Standby 자동 장애 조치)"
  type        = bool
  default     = false
}

variable "msk_broker_count" {
  description = "MSK 브로커 수 (3 AZ → 3의 배수)"
  type        = number
  default     = 3
}

variable "alb_wait_minutes" {
  description = "ArgoCD 가 Gateway 를 동기화해 ALB 가 생길 때까지 기다리는 최대 시간"
  type        = number
  default     = 25
}

variable "core_node_count" {
  description = "core 노드 그룹 최소(=초기) 대수 (학습 환경 1, 운영 2+)"
  type        = number
  default     = 1
}

variable "redis_node_type" {
  description = "ElastiCache 노드 타입"
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_replicas" {
  description = "ElastiCache Replica 수 (학습 환경 0 = 단일 노드, 운영 1+ = Multi-AZ)"
  type        = number
  default     = 0
}
