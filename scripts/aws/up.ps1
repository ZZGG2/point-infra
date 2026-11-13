<#
.SYNOPSIS
  AWS Main 전체 구축: ECR → 백엔드 이미지 푸시 → terraform apply(전체) → 프론트엔드 업로드
.DESCRIPTION
  학습/검증용 로컬 실행 스크립트. 운영 경로는 CI(terraform-apply.yml, backend/frontend ci.yml)가 같은 일을 한다.
  사전 조건: terraform, aws CLI(인증 완료), docker(실행 중), node 20+, pwsh 7
  최초 1회: infra/terraform/envs/aws-main 에서 backend.hcl, terraform.tfvars 준비 (README 참조)
#>
param(
  [string]$BackendDir  = (Join-Path $PSScriptRoot '..\..\..\point-backend'),
  [string]$FrontendDir = (Join-Path $PSScriptRoot '..\..\..\point-frontend'),
  [switch]$AutoApprove
)
$ErrorActionPreference = 'Stop'
$envDir = Resolve-Path (Join-Path $PSScriptRoot '..\..\infra\terraform\envs\aws-main')
$approve = if ($AutoApprove) { @('-auto-approve') } else { @() }

function Invoke-Checked([scriptblock]$Block, [string]$What) {
  & $Block
  if ($LASTEXITCODE -ne 0) { throw "$What 실패 (exit $LASTEXITCODE)" }
}

# 이미지 태그 = 백엔드 커밋 (ECR 불변 태그 → 커밋되지 않은 변경이 있으면 시각을 붙여 새 태그)
$sha = (git -C $BackendDir rev-parse --short HEAD).Trim()
$dirty = (git -C $BackendDir status --porcelain --untracked-files=no)
$tag = if ($dirty) { "sha-$sha-$(Get-Date -Format 'yyyyMMddHHmm')" } else { "sha-$sha" }
Write-Host "==> image tag: $tag"

Write-Host '==> [1/4] terraform init + ECR'
Invoke-Checked { terraform -chdir="$envDir" init -input=false -backend-config=backend.hcl } 'terraform init'
Invoke-Checked { terraform -chdir="$envDir" apply -input=false @approve -target='module.ecr' } 'ECR apply'

Write-Host '==> [2/4] 백엔드 이미지 빌드·푸시'
& (Join-Path $PSScriptRoot 'build-push.ps1') -BackendDir $BackendDir -Tag $tag

Write-Host '==> [3/4] terraform apply (전체, 30~45분: MSK 생성 + ArgoCD 동기화 + ALB 대기)'
Invoke-Checked { terraform -chdir="$envDir" apply -input=false @approve -var "image_tag=$tag" } 'terraform apply'

Write-Host '==> [4/4] 프론트엔드 빌드·업로드'
& (Join-Path $PSScriptRoot 'deploy-frontend.ps1') -FrontendDir $FrontendDir

Write-Host ''
terraform -chdir="$envDir" output web_url
