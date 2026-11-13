locals {
  name         = "point-main"
  cluster_name = "point-main-eks"
  tags = {
    project     = "point-platform"
    env         = "main"
    managed-by  = "terraform"
    cost-center = "portfolio"
  }
}

module "vpc" {
  source       = "../../modules/aws/vpc"
  name         = local.name
  cluster_name = local.cluster_name
  cidr         = "10.10.0.0/16"
  azs          = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]

  public_subnets = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
  app_subnets    = ["10.10.32.0/19", "10.10.64.0/19", "10.10.96.0/19"]
  data_subnets   = ["10.10.128.0/24", "10.10.129.0/24", "10.10.130.0/24"]

  single_nat_gateway = var.single_nat_gateway
  tags               = local.tags
}

module "eks" {
  source       = "../../modules/aws/eks"
  cluster_name = local.cluster_name
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.app_subnet_ids
  tags         = local.tags
}

module "aurora" {
  source                     = "../../modules/aws/aurora"
  name                       = local.name
  vpc_id                     = module.vpc.vpc_id
  db_subnet_group            = module.vpc.database_subnet_group
  allowed_security_group_ids = [module.eks.node_security_group_id] # TODO: + MSK Connect SG
  tags                       = local.tags
}

# TODO: module "karpenter"   { source = "../../modules/aws/karpenter" }
# TODO: module "elasticache" { source = "../../modules/aws/elasticache" }
# TODO: module "msk"         { source = "../../modules/aws/msk" }
# TODO: module "ecr"         { source = "../../modules/aws/ecr" }
# TODO: module "edge"        { source = "../../modules/aws/edge" }
# TODO: module "vpn_aws_side" — GCP HA VPN 인터페이스 IP를 변수로 받아 생성
