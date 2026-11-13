<#
.SYNOPSIS
  프론트엔드 빌드 → S3 업로드 → CloudFront 무효화
  API 는 같은 출처(/api/*, CloudFront → ALB)라 별도 API 주소 설정이 필요 없다.
#>
param(
  [string]$FrontendDir = (Join-Path $PSScriptRoot '..\..\..\point-frontend')
)
$ErrorActionPreference = 'Stop'
$envDir = Resolve-Path (Join-Path $PSScriptRoot '..\..\infra\terraform\envs\aws-main')
$bucket = (terraform "-chdir=$envDir" output -raw web_bucket).Trim()
$distId = (terraform "-chdir=$envDir" output -raw cloudfront_distribution_id).Trim()

Push-Location $FrontendDir
try {
  npm ci --no-audit --no-fund
  if ($LASTEXITCODE -ne 0) { throw 'npm ci 실패' }
  npm run build
  if ($LASTEXITCODE -ne 0) { throw 'npm run build 실패' }

  # 해시가 붙은 정적 파일은 오래 캐시, index.html 은 매번 재검증
  aws s3 sync dist "s3://$bucket" --delete --exclude index.html --cache-control 'public,max-age=31536000,immutable'
  if ($LASTEXITCODE -ne 0) { throw 'S3 업로드 실패' }
  aws s3 cp dist/index.html "s3://$bucket/index.html" --cache-control 'no-cache'
  if ($LASTEXITCODE -ne 0) { throw 'index.html 업로드 실패' }
} finally { Pop-Location }

aws cloudfront create-invalidation --distribution-id $distId --paths '/*' --query 'Invalidation.Id' --output text
