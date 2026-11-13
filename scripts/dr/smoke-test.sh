#!/usr/bin/env bash
# 로그인 → 잔액 조회 → 내역 조회, 그리고 이벤트 경로가 503 인지 확인
set -euo pipefail
BASE="${DR_BASE_URL:?DR_BASE_URL required}"
# TODO: TOKEN=$(curl -sf -X POST "$BASE/api/auth/login" -d '...' | jq -r .data.accessToken)
# curl -sf -H "Authorization: Bearer $TOKEN" "$BASE/api/points/balance"
# test "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/events/active")" = "503"
echo "TODO: smoke test against ${BASE}"
