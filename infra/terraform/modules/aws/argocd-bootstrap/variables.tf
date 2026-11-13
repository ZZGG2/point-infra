variable "cluster_name" {
  description = "EKS 클러스터 이름 (LB Controller 값)"
  type        = string
}
variable "region" {
  description = "AWS 리전 (LB Controller 값)"
  type        = string
}
variable "vpc_id" {
  description = "VPC ID (LB Controller 값 — 파드에서 IMDS 조회가 막혀 있어 명시)"
  type        = string
}
variable "git_repo_url" {
  description = "GitOps 원천 저장소 (point-infra)"
  type        = string
}
variable "git_revision" {
  description = "동기화할 브랜치/태그"
  type        = string
  default     = "main"
}
variable "apps_path" {
  description = "앱 kustomize 경로 (k8s/overlays/aws 또는 데모 시드 포함 k8s/overlays/aws-demo)"
  type        = string
  default     = "k8s/overlays/aws"
}
variable "images" {
  description = "kustomize 이미지 이름 → 실제 이미지 (레지스트리/이름:태그)"
  type        = map(string)
}
variable "addon_replicas" {
  description = "애드온 컨트롤러 레플리카 수 (학습 환경 1, 운영 2)"
  type        = number
  default     = 1
}
variable "argocd_chart_version" {
  description = "argo-cd Helm 차트 버전"
  type        = string
  default     = "10.18.0"
}
variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm 차트 버전"
  type        = string
  default     = "2.0.8"
}
variable "lbc_chart_version" {
  description = "aws-load-balancer-controller Helm 차트 버전"
  type        = string
  default     = "3.6.2"
}
variable "gateway_api_version" {
  description = "Gateway API 표준 CRD 버전 (LB Controller 가 빌드된 버전과 맞춤)"
  type        = string
  default     = "v1.6.0"
}
variable "eso_chart_version" {
  description = "external-secrets Helm 차트 버전"
  type        = string
  default     = "2.15.0"
}
variable "keda_chart_version" {
  description = "keda Helm 차트 버전"
  type        = string
  default     = "2.21.0"
}
