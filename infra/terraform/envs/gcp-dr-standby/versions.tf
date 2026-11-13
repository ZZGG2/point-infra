terraform {
  required_version = ">= 1.10"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
  backend "gcs" {
    bucket = "point-platform-tfstate-dr-CHANGE_ME"
    prefix = "envs/gcp-dr-standby"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
