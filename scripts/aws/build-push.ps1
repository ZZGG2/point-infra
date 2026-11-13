<#
.SYNOPSIS
  monolith / event-service 이미지를 빌드해 ECR 에 푸시 (이미 있는 태그는 건너뜀 — 불변 태그)
#>
param(
  [Parameter(Mandatory)][string]$Tag,
  [string]$BackendDir = (Join-Path $PSScriptRoot '..\..\..\point-backend')
)
$ErrorActionPreference = 'Stop'
$envDir = Resolve-Path (Join-Path $PSScriptRoot '..\..\infra\terraform\envs\aws-main')
$region = 'ap-northeast-2'

$repos = terraform -chdir="$envDir" output -json ecr_repository_urls | ConvertFrom-Json
$registry = ($repos.monolith -split '/')[0]

aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry
if ($LASTEXITCODE -ne 0) { throw 'ECR 로그인 실패' }

foreach ($module in 'monolith', 'event-service') {
  $image = "$($repos.$module):$Tag"
  aws ecr describe-images --region $region --repository-name $module --image-ids imageTag=$Tag *> $null
  if ($LASTEXITCODE -eq 0) { Write-Host "skip $image (already pushed)"; continue }

  Write-Host "build $image"
  docker build --platform linux/amd64 -f (Join-Path $BackendDir "$module/Dockerfile") --build-arg MODULE=$module -t $image $BackendDir
  if ($LASTEXITCODE -ne 0) { throw "$module 빌드 실패" }
  docker push $image
  if ($LASTEXITCODE -ne 0) { throw "$module 푸시 실패" }
}
