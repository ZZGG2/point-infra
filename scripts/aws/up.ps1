<#
.SYNOPSIS
  AWS Main 전체 구축: ECR → 이미지(monolith, event-service, web) 푸시 → terraform plan → (확인) → apply
.DESCRIPTION
  학습/검증용 로컬 실행 스크립트. 운영 경로는 CI 가 같은 일을 한다.
  사전 조건: terraform, aws CLI(인증 완료), docker(실행 중), pwsh 7, GitOps 저장소에 main push 완료
  최초 1회: infra/terraform/envs/aws-main 에서 backend.hcl, terraform.tfvars 준비 (README 참조)
#>
param(
  [string]$BackendDir  = (Join-Path $PSScriptRoot '..\..\..\point-backend'),
  [string]$FrontendDir = (Join-Path $PSScriptRoot '..\..\..\point-frontend')
)
$ErrorActionPreference = 'Stop'
$envDir = Resolve-Path (Join-Path $PSScriptRoot '..\..\infra\terraform\envs\aws-main')

function Invoke-Checked([scriptblock]$Block, [string]$What) {
  & $Block
  if ($LASTEXITCODE -ne 0) { throw "$What 실패 (exit $LASTEXITCODE)" }
}

# 이미지 태그 = 저장소 커밋 (ECR 불변 태그 → 커밋되지 않은 변경이 있으면 시각을 붙여 새 태그)
function Get-ImageTag([string]$Dir) {
  $sha = (git -C $Dir rev-parse --short HEAD).Trim()
  $dirty = (git -C $Dir status --porcelain --untracked-files=no)
  if ($dirty) { "sha-$sha-$(Get-Date -Format 'yyyyMMddHHmm')" } else { "sha-$sha" }
}
$tag = Get-ImageTag $BackendDir
$webTag = Get-ImageTag $FrontendDir
Write-Host "==> image tags: backend=$tag web=$webTag"

Write-Host '==> [1/3] terraform init + ECR'
Invoke-Checked { terraform "-chdir=$envDir" init -input=false "-backend-config=backend.hcl" } 'terraform init'
Invoke-Checked { terraform "-chdir=$envDir" apply -input=false "-target=module.ecr" } 'ECR apply'

Write-Host '==> [2/3] 이미지 빌드·푸시'
& (Join-Path $PSScriptRoot 'build-push.ps1') -BackendDir $BackendDir -FrontendDir $FrontendDir -Tag $tag -WebTag $webTag

Write-Host '==> [3/3] terraform apply (최초 30~45분: MSK 생성 + ArgoCD 동기화 + ALB 대기)'
Invoke-Checked { terraform "-chdir=$envDir" apply -input=false -var "image_tag=$tag" -var "web_image_tag=$webTag" } 'terraform apply'

Write-Host ''
terraform "-chdir=$envDir" output web_url
