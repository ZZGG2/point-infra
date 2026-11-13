# GKE에 ArgoCD 설치 + root Application(App of Apps) 1개만 생성.
# 이후 모든 워크로드는 Git(k8s/argocd/root-gcp-dr.yaml)이 채운다. (ADR-0009)
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
}

resource "helm_release" "root_app" {
  depends_on = [helm_release.argocd]
  name       = "root-gcp-dr"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  namespace  = "argocd"

  values = [yamlencode({
    applications = {
      root-gcp-dr = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.git_repo_url
          targetRevision = "main"
          path           = "k8s/argocd/gcp-dr"
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
        syncPolicy  = { automated = { prune = true, selfHeal = true } }
      }
    }
  })]
}
