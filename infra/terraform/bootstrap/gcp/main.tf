# Terraform state 저장소 (gcp-dr-standby, gcp-dr-compute 전용)
# AWS 장애 시에도 DR apply가 가능하도록 state를 GCP에 둔다. (ADR-0010)
terraform {
  required_version = ">= 1.10"
  required_providers { google = { source = "hashicorp/google", version = "~> 6.0" } }
}
variable "project_id" { type = string }
variable "bucket_name" { type = string }

provider "google" {
  project = var.project_id
  region  = "asia-northeast3"
}

resource "google_storage_bucket" "state" {
  name                        = var.bucket_name
  location                    = "ASIA-NORTHEAST3"
  uniform_bucket_level_access = true
  versioning { enabled = true }
  lifecycle { prevent_destroy = true }
}
