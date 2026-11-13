terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket       = "point-platform-tfstate-CHANGE_ME"
    key          = "envs/aws-main/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true # S3 네이티브 락 (DynamoDB 불필요)
  }
}

provider "aws" {
  region = "ap-northeast-2"
  default_tags { tags = local.tags }
}
