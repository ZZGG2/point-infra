# EKS: core(monolith) = Managed NodeGroup On-Demand / event = Karpenter Spot (modules/aws/karpenter)
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_endpoint_public_access           = true # TODO: 운영 시 허용 CIDR 제한 또는 private
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    # before_compute: 노드 그룹보다 먼저 설치 → 첫 노드부터 Prefix Delegation·Pod Identity 적용
    vpc-cni = {
      before_compute       = true
      configuration_values = jsonencode({ env = { ENABLE_PREFIX_DELEGATION = "true" } })
    }
    eks-pod-identity-agent = { before_compute = true }
  }

  eks_managed_node_groups = {
    core = {
      instance_types = var.core_instance_types
      capacity_type  = "ON_DEMAND"
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      labels         = { workload = "core" }
    }
  }

  node_security_group_tags = { "karpenter.sh/discovery" = var.cluster_name }
  tags                     = var.tags
}
