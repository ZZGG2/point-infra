<#
.SYNOPSIS
  monolith / event-service / web 이미지를 빌드해 ECR 에 푸시 (이미 있는 태그는 건너뜀 — 불변 태그)
#>
param(
  [Parameter(Mandatory)][string]$Tag,
  [Parameter(Mandatory)][string]$WebTag,
  [string]$BackendDir = (Join-Path $PSScriptRoot '..\..\..\point-backend'),
  [string]$FrontendDir = (Join-Path $PSScriptRoot '..\..\..\point-frontend')
)
$ErrorActionPreference = 'Stop'
$region = 'ap-northeast-2'
$account = (aws sts get-caller-identity --query Account --output text).Trim()
$registry = "$account.dkr.ecr.$region.amazonaws.com"

aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry
if ($LASTEXITCODE -ne 0) { throw 'ECR 로그인 실패' }

$images = @(
  @{ Repo = 'monolith';      Tag = $Tag;    Context = $BackendDir;  Dockerfile = (Join-Path $BackendDir 'monolith/Dockerfile');      Args = @('--build-arg', 'MODULE=monolith') },
  @{ Repo = 'event-service'; Tag = $Tag;    Context = $BackendDir;  Dockerfile = (Join-Path $BackendDir 'event-service/Dockerfile'); Args = @('--build-arg', 'MODULE=event-service') },
  @{ Repo = 'web';           Tag = $WebTag; Context = $FrontendDir; Dockerfile = (Join-Path $FrontendDir 'Dockerfile');              Args = @() }
)

foreach ($img in $images) {
  $ref = "$registry/$($img.Repo):$($img.Tag)"
  aws ecr describe-images --region $region --repository-name $img.Repo --image-ids "imageTag=$($img.Tag)" *> $null
  if ($LASTEXITCODE -eq 0) { Write-Host "skip $ref (already pushed)"; continue }

  Write-Host "build $ref"
  docker build --platform linux/amd64 -f $img.Dockerfile @($img.Args) -t $ref $img.Context
  if ($LASTEXITCODE -ne 0) { throw "$($img.Repo) 빌드 실패" }
  docker push $ref
  if ($LASTEXITCODE -ne 0) { throw "$($img.Repo) 푸시 실패" }
}
