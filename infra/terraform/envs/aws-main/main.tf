locals {
  name         = "point-main"
  cluster_name = "point-main-eks"
  alb_name     = "point-main-alb" # k8s/overlays/aws/gateway.yaml 의 LoadBalancerConfiguration.loadBalancerName 과 일치
  tags = {
    project     = "point-platform"
    env         = "main"
    owner       = "point-platform"
    managed-by  = "terraform"
    cost-center = "portfolio"
  }
  admin_cidrs = length(var.admin_cidrs) > 0 ? var.admin_cidrs : ["${chomp(data.http.my_ip.response_body)}/32"]
  # 도메인·ACM(HTTPS 443) 전까지 ALB 는 관리자 IP 만 허용 (security.md: 0.0.0.0/0 은 ALB 443 만)
  alb_ingress_cidrs = length(var.alb_ingress_cidrs) > 0 ? var.alb_ingress_cidrs : local.admin_cidrs
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

# ---------------------------------------------------------------- 네트워크
module "vpc" {
  source       = "../../modules/aws/vpc"
  name         = local.name
  cluster_name = local.cluster_name
  cidr         = "10.10.0.0/16"
  azs          = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]

  public_subnets = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
  app_subnets    = ["10.10.32.0/19", "10.10.64.0/19", "10.10.96.0/19"]
  data_subnets   = ["10.10.128.0/24", "10.10.129.0/24", "10.10.130.0/24"]

  single_nat_gateway         = var.single_nat_gateway
  enable_interface_endpoints = var.enable_interface_endpoints
  tags                       = local.tags
}

# ---------------------------------------------------------------- 컴퓨팅
module "eks" {
  source              = "../../modules/aws/eks"
  cluster_name        = local.cluster_name
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.app_subnet_ids
  public_access_cidrs = local.admin_cidrs
  core_min_size       = var.core_node_count
  tags                = local.tags
}

module "karpenter" {
  source           = "../../modules/aws/karpenter"
  depends_on       = [module.eks] # destroy 시 노드 그룹보다 먼저 Helm 해제
  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
  tags             = local.tags
}

module "ecr" {
  source       = "../../modules/aws/ecr"
  repositories = ["monolith", "event-service", "web"]
  tags         = local.tags
}

# ---------------------------------------------------------------- 데이터
module "rds" {
  source                     = "../../modules/aws/rds"
  name                       = local.name
  vpc_id                     = module.vpc.vpc_id
  db_subnet_group            = module.vpc.database_subnet_group
  allowed_security_group_ids = [module.eks.node_security_group_id] # TODO: + MSK Connect SG
  instance_class             = var.rds_instance_class
  multi_az                   = var.rds_multi_az
  tags                       = local.tags
}

module "elasticache" {
  source                     = "../../modules/aws/elasticache"
  name                       = local.name
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
  node_type                  = var.redis_node_type
  replicas                   = var.redis_replicas
  tags                       = local.tags
}

module "msk" {
  source                     = "../../modules/aws/msk"
  name                       = local.name
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
  broker_count               = var.msk_broker_count
  tags                       = local.tags
}

# ---------------------------------------------------------------- 앱 연결 정보 (Secrets Manager → External Secrets)
# 엔드포인트·자격 증명은 Git 에 두지 않는다. ExternalSecret(k8s/overlays/aws)이 이 시크릿을 그대로 env 로 만든다.
resource "aws_secretsmanager_secret" "app" {
  for_each                = toset(["monolith", "event-service", "db-bootstrap"])
  name                    = "${local.name}/${each.key}"
  description             = "${each.key} runtime config (External Secrets)"
  recovery_window_in_days = 0 # 학습 환경: destroy 후 같은 이름으로 즉시 재생성
}

resource "aws_secretsmanager_secret_version" "monolith" {
  secret_id = aws_secretsmanager_secret.app["monolith"].id
  secret_string = jsonencode({
    DB_URL                         = "jdbc:postgresql://${module.rds.address}:${module.rds.port}/point?sslmode=require"
    DB_USERNAME                    = module.rds.app_username
    DB_PASSWORD                    = module.rds.app_password
    KAFKA_BOOTSTRAP                = module.msk.bootstrap_brokers_tls
    SPRING_KAFKA_SECURITY_PROTOCOL = "SSL"
  })
}

resource "aws_secretsmanager_secret_version" "event_service" {
  secret_id = aws_secretsmanager_secret.app["event-service"].id
  secret_string = jsonencode({
    REDIS_HOST                     = module.elasticache.primary_endpoint
    REDIS_PORT                     = tostring(module.elasticache.port)
    SPRING_DATA_REDIS_SSL_ENABLED  = "true"
    KAFKA_BOOTSTRAP                = module.msk.bootstrap_brokers_tls
    SPRING_KAFKA_SECURITY_PROTOCOL = "SSL"
  })
}

# db-init Job(k8s/overlays/aws/db-init.yaml) 전용: 마스터 계정으로 app_rw 생성
resource "aws_secretsmanager_secret_version" "db_bootstrap" {
  secret_id = aws_secretsmanager_secret.app["db-bootstrap"].id
  secret_string = jsonencode({
    PGHOST       = module.rds.address
    PGPORT       = tostring(module.rds.port)
    PGDATABASE   = "point"
    PGUSER       = module.rds.master_username
    PGPASSWORD   = module.rds.master_password
    APP_PASSWORD = module.rds.app_password
  })
}

# ---------------------------------------------------------------- 애드온 IAM (EKS Pod Identity)
module "lbc_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.12"

  name                            = "${local.name}-aws-lbc"
  attach_aws_lb_controller_policy = true
  associations = {
    this = { cluster_name = module.eks.cluster_name, namespace = "kube-system", service_account = "aws-load-balancer-controller" }
  }
  tags = local.tags
}

module "eso_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.12"

  name                                  = "${local.name}-external-secrets"
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = [for s in aws_secretsmanager_secret.app : s.arn]
  external_secrets_create_permission    = false
  associations = {
    this = { cluster_name = module.eks.cluster_name, namespace = "external-secrets", service_account = "external-secrets" }
  }
  tags = local.tags
}

# ALB 보안 그룹 — Gateway 의 LoadBalancerConfiguration.securityGroups 가 이름으로 참조
resource "aws_security_group" "alb" {
  name        = local.alb_name
  description = "Gateway ALB"
  vpc_id      = module.vpc.vpc_id
  tags        = { Name = local.alb_name }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each          = toset(local.alb_ingress_cidrs)
  security_group_id = aws_security_group.alb.id
  description       = "HTTP (TODO: 도메인·ACM 후 443 공개, 80 은 리다이렉트)"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb" {
  security_group_id = aws_security_group.alb.id
  description       = "To targets in VPC"
  cidr_ipv4         = module.vpc.vpc_cidr
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------- GitOps 부트스트랩
module "argocd" {
  source = "../../modules/aws/argocd-bootstrap"
  depends_on = [
    module.karpenter, module.lbc_pod_identity, module.eso_pod_identity,
    aws_secretsmanager_secret_version.monolith, aws_secretsmanager_secret_version.event_service,
    aws_secretsmanager_secret_version.db_bootstrap, aws_security_group.alb,
  ]

  cluster_name = module.eks.cluster_name
  region       = var.region
  vpc_id       = module.vpc.vpc_id
  git_repo_url = var.git_repo_url
  git_revision = var.git_revision
  apps_path    = var.apps_path
  images = {
    monolith        = "${module.ecr.repository_urls["monolith"]}:${var.image_tag}"
    "event-service" = "${module.ecr.repository_urls["event-service"]}:${var.image_tag}"
    web             = "${module.ecr.repository_urls["web"]}:${var.web_image_tag}"
  }
}

# ---------------------------------------------------------------- ALB(Gateway 가 생성) 대기 → WAF 연결
resource "terraform_data" "wait_alb" {
  depends_on       = [module.argocd]
  triggers_replace = ["gateway-api"] # 값을 바꾸면 ALB 대기·WAF 연결을 다시 수행

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-NonInteractive", "-Command"]
    command     = <<-PS
      $deadline = (Get-Date).AddMinutes(${var.alb_wait_minutes})
      while ((Get-Date) -lt $deadline) {
        $state = aws elbv2 describe-load-balancers --region ${var.region} --names ${local.alb_name} --query "LoadBalancers[0].State.Code" --output text 2>$null
        if ($LASTEXITCODE -eq 0 -and $state -eq 'active') { Write-Output "ALB ${local.alb_name} active"; exit 0 }
        Start-Sleep -Seconds 20
      }
      Write-Error "ALB ${local.alb_name} 이 ${var.alb_wait_minutes}분 안에 생성되지 않았습니다. kubectl -n argocd get applications / kubectl -n point describe gateway point 로 확인하세요."
      exit 1
    PS
  }
}

data "aws_lb" "gateway" {
  depends_on = [terraform_data.wait_alb]
  name       = local.alb_name
}

module "waf" {
  source  = "../../modules/aws/waf"
  name    = local.name
  alb_arn = data.aws_lb.gateway.arn
  tags    = local.tags
}

# TODO: Route 53 호스팅 영역 + ACM → Gateway HTTPS 리스너 (도메인 확보 시)
# TODO: module "vpn_aws_side" — GCP HA VPN 인터페이스 IP를 변수로 받아 생성 (GCP DR 구축 시)
