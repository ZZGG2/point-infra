# 3-Tier VPC: Public / Private-App(/19, EKS) / Private-Data
# docs/01-architecture/network-design.md 참조
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.name}-vpc"
  cidr = var.cidr
  azs  = var.azs

  public_subnets   = var.public_subnets
  private_subnets  = var.app_subnets
  database_subnets = var.data_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway # 학습 환경 true (FinOps), 운영 false
  one_nat_gateway_per_az = !var.single_nat_gateway

  create_database_subnet_group = true
  enable_dns_hostnames         = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.cluster_name
  }
  tags = var.tags
}

# TODO: VPC Endpoints (S3 GW, ecr.api, ecr.dkr, sts, secretsmanager, logs)
