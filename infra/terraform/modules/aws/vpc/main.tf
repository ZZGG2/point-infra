# 3-Tier VPC: Public / Private-App(/19, EKS) / Private-Data
# docs/01-architecture/network-design.md 참조
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

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

  public_subnet_tags = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.cluster_name
  }
  tags = var.tags
}

# VPC Endpoint: NAT 데이터 처리 비용 절감 + 망분리 (network-design.md §3)
resource "aws_security_group" "endpoints" {
  count       = var.enable_interface_endpoints ? 1 : 0
  name        = "${var.name}-vpce"
  description = "Interface VPC endpoints (HTTPS from VPC)"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }
  tags = merge(var.tags, { Name = "${var.name}-vpce" })
}

module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.21"

  vpc_id = module.vpc.vpc_id

  endpoints = merge(
    {
      s3 = {
        service         = "s3"
        service_type    = "Gateway"
        route_table_ids = module.vpc.private_route_table_ids
        tags            = { Name = "${var.name}-s3" }
      }
    },
    var.enable_interface_endpoints ? {
      for svc in ["ecr.api", "ecr.dkr", "sts", "secretsmanager", "logs"] : replace(svc, ".", "_") => {
        service             = svc
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.endpoints[0].id]
        tags                = { Name = "${var.name}-${svc}" }
      }
    } : {}
  )
  tags = var.tags
}
