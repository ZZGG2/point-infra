# EKS 에 ArgoCD 설치 + Application 등록 (ADR-0009: Terraform 은 ArgoCD 설치·등록까지, 나머지는 Git)
#
# 공개 저장소(point-infra)에 계정 ID·VPC ID 같은 환경 값을 커밋하지 않기 위해,
# 환경 값이 필요한 Application(애드온 Helm 값, 앱 이미지 주소)은 여기서 값만 주입해 등록한다.
# 매니페스트 본문은 모두 Git(k8s/) 또는 공식 Helm 차트에서 온다.
locals {
  sync = {
    automated   = { prune = true, selfHeal = true }
    syncOptions = ["CreateNamespace=true", "ServerSideApply=true", "SkipDryRunOnMissingResource=true"]
    # CRD 를 제공하는 애드온보다 먼저 동기화되면 실패하므로 재시도
    retry = { limit = 20, backoff = { duration = "30s", factor = 2, maxDuration = "5m" } }
  }
  in_cluster = "https://kubernetes.default.svc"
  # 삭제 시 하위 리소스까지 정리 (Ingress → ALB, NodePool → Karpenter 노드)
  cascade = ["resources-finalizer.argocd.argoproj.io"]

  git = { repoURL = var.git_repo_url, targetRevision = var.git_revision }

  applications = {
    # Git 이 관리하는 ArgoCD 설정 (AppProject, Sync Window)
    root-aws = {
      namespace   = "argocd"
      project     = "default"
      source      = merge(local.git, { path = "k8s/argocd/aws" })
      destination = { server = local.in_cluster, namespace = "argocd" }
      syncPolicy  = local.sync
    }

    # Gateway API 표준 CRD + LB Controller(차트에 gateway.k8s.aws CRD 포함).
    # 같은 Application 에 묶어 CRD 가 컨트롤러보다 먼저 적용되게 한다 (컨트롤러는 기동 시 CRD 를 감지해 Gateway 기능을 켠다)
    aws-load-balancer-controller = {
      namespace = "argocd"
      project   = "default"
      sources = [
        {
          repoURL        = "https://github.com/kubernetes-sigs/gateway-api.git"
          targetRevision = var.gateway_api_version
          path           = "config/crd/standard"
        },
        {
          repoURL        = "https://aws.github.io/eks-charts"
          chart          = "aws-load-balancer-controller"
          targetRevision = var.lbc_chart_version
          helm = {
            valuesObject = {
              clusterName    = var.cluster_name
              region         = var.region
              vpcId          = var.vpc_id
              serviceAccount = { name = "aws-load-balancer-controller" } # Pod Identity 연결 대상
              nodeSelector   = { workload = "core" }
              replicaCount   = var.addon_replicas
              # 차트가 렌더링마다 자체 서명 인증서를 새로 만들면 ArgoCD 동기화 시 webhook CA 와 어긋난다
              # → Terraform 이 만든 고정 인증서를 넘긴다
              webhookTLS = {
                caCert = tls_self_signed_cert.lbc_ca.cert_pem
                cert   = tls_locally_signed_cert.lbc_webhook.cert_pem
                key    = tls_private_key.lbc_webhook.private_key_pem
              }
            }
          }
        },
      ]
      destination = { server = local.in_cluster, namespace = "kube-system" }
      syncPolicy  = local.sync
    }

    external-secrets = {
      namespace = "argocd"
      project   = "default"
      source = {
        repoURL        = "https://charts.external-secrets.io"
        chart          = "external-secrets"
        targetRevision = var.eso_chart_version
        helm = {
          valuesObject = {
            serviceAccount = { name = "external-secrets" } # Pod Identity 연결 대상
            nodeSelector   = { workload = "core" }
          }
        }
      }
      destination = { server = local.in_cluster, namespace = "external-secrets" }
      syncPolicy  = local.sync
    }

    keda = {
      namespace = "argocd"
      project   = "default"
      source = {
        repoURL        = "https://kedacore.github.io/charts"
        chart          = "keda"
        targetRevision = var.keda_chart_version
        helm           = { valuesObject = { nodeSelector = { workload = "core" } } }
      }
      destination = { server = local.in_cluster, namespace = "keda" }
      syncPolicy  = local.sync
    }

    platform-external-secrets = {
      namespace   = "argocd"
      project     = "default"
      source      = merge(local.git, { path = "k8s/platform/external-secrets/aws" })
      destination = { server = local.in_cluster, namespace = "external-secrets" }
      syncPolicy  = local.sync
    }

    platform-karpenter = {
      namespace   = "argocd"
      project     = "default"
      finalizers  = local.cascade
      source      = merge(local.git, { path = "k8s/platform/karpenter" })
      destination = { server = local.in_cluster }
      syncPolicy  = local.sync
    }

    apps-aws = {
      namespace  = "argocd"
      project    = "default"
      finalizers = local.cascade
      source = merge(local.git, {
        path      = var.apps_path
        kustomize = { images = [for name, url in var.images : "${name}=${url}"] }
      })
      destination = { server = local.in_cluster, namespace = "point" }
      syncPolicy  = local.sync
    }
  }
}

# ---------------------------------------------------------------- LB Controller webhook 인증서 (10년, 클러스터 내부 전용)
resource "tls_private_key" "lbc_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "lbc_ca" {
  private_key_pem       = tls_private_key.lbc_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600
  allowed_uses          = ["cert_signing", "key_encipherment", "digital_signature"]
  subject { common_name = "aws-load-balancer-controller-ca" }
}

resource "tls_private_key" "lbc_webhook" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "lbc_webhook" {
  private_key_pem = tls_private_key.lbc_webhook.private_key_pem
  dns_names = [
    "aws-load-balancer-webhook-service.kube-system.svc",
    "aws-load-balancer-webhook-service.kube-system.svc.cluster.local",
  ]
  subject { common_name = "aws-load-balancer-webhook-service.kube-system.svc" }
}

resource "tls_locally_signed_cert" "lbc_webhook" {
  cert_request_pem      = tls_cert_request.lbc_webhook.cert_request_pem
  ca_private_key_pem    = tls_private_key.lbc_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.lbc_ca.cert_pem
  validity_period_hours = 87600
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true

  values = [yamlencode({
    global        = { nodeSelector = { workload = "core" } }
    dex           = { enabled = false }
    notifications = { enabled = false }
    configs       = { params = { "server.insecure" = true } } # 접속은 kubectl port-forward
  })]
}

resource "helm_release" "apps" {
  depends_on = [helm_release.argocd]
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = "argocd"

  values = [yamlencode({ applications = local.applications })]
}
