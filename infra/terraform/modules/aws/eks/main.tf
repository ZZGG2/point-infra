# EKS: core(monolith) = Managed NodeGroup On-Demand / event = Karpenter Spot (modules/aws/karpenter)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_endpoint_public_access           = true
  cluster_endpoint_public_access_cidrs     = var.public_access_cidrs # terraform 실행 PC 만 허용
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    vpc-cni                = { most_recent = true, before_compute = true, configuration_values = jsonencode({ env = { ENABLE_PREFIX_DELEGATION = "true" } }) }
    eks-pod-identity-agent = { most_recent = true, before_compute = true }
  }

  eks_managed_node_groups = {
    core = {
      ami_type       = "AL2023_x86_64_STANDARD" # 1.33+ 는 AL2 AMI 미지원
      instance_types = var.core_instance_types
      capacity_type  = "ON_DEMAND"
      min_size       = var.core_min_size
      max_size       = var.core_max_size
      desired_size   = var.core_min_size
      labels         = { workload = "core" }
    }
  }

  node_security_group_tags = { "karpenter.sh/discovery" = var.cluster_name }
  tags                     = var.tags
}
