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

    aws-load-balancer-controller = {
      namespace = "argocd"
      project   = "default"
      source = {
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
          }
        }
      }
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

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true

  values = [yamlencode({
    global  = { nodeSelector = { workload = "core" } }
    dex     = { enabled = false }
    configs = { params = { "server.insecure" = true } } # 접속은 kubectl port-forward
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
