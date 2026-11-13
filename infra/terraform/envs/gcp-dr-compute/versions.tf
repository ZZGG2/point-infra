terraform {
  required_version = ">= 1.10"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
    helm   = { source = "hashicorp/helm", version = "~> 2.15" }
  }
  # AWS 장애 중에도 접근 가능해야 하므로 GCS (ADR-0010)
  backend "gcs" {
    bucket = "point-platform-tfstate-dr-CHANGE_ME"
    prefix = "envs/gcp-dr-compute"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# TODO: GKE 생성 후 helm provider 를 GKE endpoint / token 으로 구성
# provider "helm" { kubernetes { host = ..., token = ..., cluster_ca_certificate = ... } }
