# Karpenter: IAM(Pod Identity), SQS Interruption Queue, EventBridge 규칙, Helm release.
# NodePool/EC2NodeClass 는 k8s/platform/karpenter (GitOps, ADR-0009)
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.37"

  cluster_name          = var.cluster_name
  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true
  namespace                       = "kube-system"
  service_account                 = "karpenter"

  # EC2NodeClass(spec.role) 가 고정 이름으로 참조
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "KarpenterNodeRole-${var.cluster_name}"
  node_iam_role_additional_policies = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.chart_version
  wait       = true

  values = [yamlencode({
    serviceAccount = { name = module.karpenter.service_account }
    settings = {
      clusterName       = var.cluster_name
      clusterEndpoint   = var.cluster_endpoint
      interruptionQueue = module.karpenter.queue_name
    }
    # 컨트롤러는 core(Managed NodeGroup) 에서만 실행 — 자기가 띄운 노드에 올라가지 않게
    nodeSelector = { workload = "core" }
    replicas     = var.replicas
    controller = {
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  })]
}
