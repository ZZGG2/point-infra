# Aurora 에 앱 전용 계정 app_rw 를 만든다 (멱등). terraform_data.app_user 가 호출.
# 입력(환경 변수): CLUSTER_ARN, SECRET_ARN(마스터), REGION, APP_PW
$ErrorActionPreference = 'Stop'

$statements = @(
    'DO $$BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ''app_rw'') THEN CREATE ROLE app_rw LOGIN; END IF; END$$',
    "ALTER ROLE app_rw WITH LOGIN PASSWORD '$($env:APP_PW)'",
    'GRANT CONNECT, CREATE ON DATABASE point TO app_rw',   # Flyway 가 users/asset/point/cs 스키마 생성
    'GRANT USAGE, CREATE ON SCHEMA public TO app_rw'       # flyway_schema_history (PG15+ 는 public CREATE 기본 회수)
)

foreach ($sql in $statements) {
    for ($attempt = 1; ; $attempt++) {
        # 인스턴스 기동 직후에는 Data API 가 잠시 실패할 수 있어 재시도한다.
        $out = aws rds-data execute-statement --region $env:REGION `
            --resource-arn $env:CLUSTER_ARN --secret-arn $env:SECRET_ARN `
            --database point --sql $sql --output json 2>&1
        if ($LASTEXITCODE -eq 0) { break }
        if ($attempt -ge 20) {
            # 비밀번호가 로그에 남지 않도록 오류 메시지만 출력
            throw "app_rw 생성 실패: $(($out | Out-String) -replace [regex]::Escape($env:APP_PW), '****')"
        }
        Start-Sleep -Seconds 15
    }
}
Write-Output 'app_rw ready'
