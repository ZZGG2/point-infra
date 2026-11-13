terraform {
  required_version = ">= 1.10"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.95" }
    helm   = { source = "hashicorp/helm", version = "~> 2.17" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    http   = { source = "hashicorp/http", version = "~> 3.4" }
  }
  # 버킷 이름(계정 ID 포함)은 저장소에 두지 않는다 → terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "envs/aws-main/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true # S3 네이티브 락 (DynamoDB 불필요)
  }
}

provider "aws" {
  region = var.region
  default_tags { tags = local.tags }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
