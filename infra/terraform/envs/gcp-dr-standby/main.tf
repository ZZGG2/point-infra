# 상시 유지 리소스 (Pilot Light의 "불씨")
#  - VPC / 서브넷 / Private Service Access
#  - Cloud SQL (CDC 복제 대상, prevent_destroy)
#  - Global Static IP (Route 53 Secondary 레코드에 사전 등록)
#  - Artifact Registry (CI 이중 푸시), Secret Manager
#  - HA VPN + Cloud Router

locals {
  labels = {
    project    = "point-platform"
    env        = "dr-standby"
    managed-by = "terraform"
  }
}

# TODO: module "network"  { source = "../../modules/gcp/network"  ... }
# TODO: module "cloudsql" { source = "../../modules/gcp/cloudsql" ... }
# TODO: module "vpn"      { source = "../../modules/shared/vpn"   ... }

resource "google_artifact_registry_repository" "apps" {
  location      = var.region
  repository_id = "point-apps"
  format        = "DOCKER"
  labels        = local.labels
}
