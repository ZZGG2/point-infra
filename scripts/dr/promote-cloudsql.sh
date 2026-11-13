#!/usr/bin/env bash
# Cloud SQL 을 DR Primary 로 승격
#  - DRILL=true  : 클론 인스턴스를 만들어 그것을 승격 (실제 복제는 유지)
#  - DRILL=false : 실제 인스턴스 승격 (sink 계정 차단 → 앱 계정 활성화 → 시퀀스 보정)
set -euo pipefail
INSTANCE="${CLOUDSQL_INSTANCE:-point-dr}"

if [[ "${DRILL:-true}" == "true" ]]; then
  INSTANCE="${INSTANCE}-drill-$(date +%Y%m%d%H%M)"
  echo "[drill] clone → ${INSTANCE}"
  # TODO: gcloud sql instances clone point-dr "${INSTANCE}"
fi

echo "[promote] ${INSTANCE}"
# TODO: psql 로 아래 실행 (Cloud SQL Auth Proxy 또는 Private IP 경유)
#   ALTER ROLE sink_writer NOLOGIN;
#   ALTER ROLE app_rw LOGIN;
#   \i scripts/dr/fix-sequences.sql
