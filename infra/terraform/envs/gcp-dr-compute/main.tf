# 장애 시에만 apply, 복구 후 destroy.
# 실행 주체: .github/workflows/dr-failover.yml (승인 필요)
#
# 순서: GKE → ArgoCD(helm) → root-gcp-dr App → (Git) monolith + maintenance 자동 배포

# 의도적으로 terraform_remote_state(S3) 를 사용하지 않는다.
# standby 출력값은 GCS state 에서만 읽는다.
data "terraform_remote_state" "standby" {
  backend = "gcs"
  config = {
    bucket = "point-platform-tfstate-dr-CHANGE_ME"
    prefix = "envs/gcp-dr-standby"
  }
}

# TODO: module "gke" { source = "../../modules/gcp/gke" ... }

# TODO: module "argocd" {
#   source       = "../../modules/gcp/argocd-bootstrap"
#   git_repo_url = var.git_repo_url
#   depends_on   = [module.gke]
# }
