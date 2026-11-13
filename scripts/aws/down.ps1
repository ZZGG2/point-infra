<#
.SYNOPSIS
  AWS Main 전체 삭제. Terraform 밖에서 생긴 리소스(Gateway → ALB, Karpenter → EC2)를 먼저 정리한 뒤 destroy.
  (순서를 지키지 않으면 ALB/ENI 가 남아 VPC 삭제가 실패한다)
#>
param([switch]$AutoApprove)
$ErrorActionPreference = 'Stop'
$envDir = Resolve-Path (Join-Path $PSScriptRoot '..\..\infra\terraform\envs\aws-main')
$region = 'ap-northeast-2'
$cluster = 'point-main-eks'
$albName = 'point-main-alb'
$approve = if ($AutoApprove) { @('-auto-approve') } else { @() }

function Wait-Until([scriptblock]$Done, [string]$What, [int]$Minutes = 15) {
  $deadline = (Get-Date).AddMinutes($Minutes)
  while (-not (& $Done)) {
    if ((Get-Date) -gt $deadline) { Write-Warning "$What 대기 시간 초과 — destroy 를 계속 진행합니다"; return }
    Start-Sleep -Seconds 15
  }
  Write-Host "ok: $What"
}

aws eks describe-cluster --region $region --name $cluster *> $null
if ($LASTEXITCODE -eq 0) {
  aws eks update-kubeconfig --region $region --name $cluster | Out-Null

  Write-Host '==> ArgoCD 앱 삭제 (finalizer 로 Gateway(ALB)·NodePool 까지 정리)'
  kubectl -n argocd delete application apps-aws platform-karpenter --ignore-not-found --wait=true --timeout=10m

  Wait-Until { aws elbv2 describe-load-balancers --region $region --names $albName *> $null; $LASTEXITCODE -ne 0 } 'ALB 삭제'
  Wait-Until {
    $ids = aws ec2 describe-instances --region $region `
      --filters "Name=tag:karpenter.sh/nodepool,Values=*" "Name=tag:kubernetes.io/cluster/$cluster,Values=owned" "Name=instance-state-name,Values=pending,running,stopping" `
      --query 'Reservations[].Instances[].InstanceId' --output text
    [string]::IsNullOrWhiteSpace($ids)
  } 'Karpenter 노드 종료'
}

Write-Host '==> terraform destroy'
terraform "-chdir=$envDir" destroy -input=false @approve
if ($LASTEXITCODE -ne 0) { throw 'terraform destroy 실패' }
