#!/usr/bin/env bash
# Cloud SQL 을 DR Primary 로 승격
# usage: promote-cloudsql.sh prepare | promote
#  - DRILL=true  : 클론 인스턴스를 만들어 그것을 승격 (실제 복제는 유지)
#  - DRILL=false : 실제 인스턴스 승격 (sink 계정 차단 → 앱 계정 활성화 → 시퀀스·잔액 보정)
#
# Cloud SQL 은 Private IP 전용 → GitHub runner 에서 psql 불가.
#  prepare : runner 에서 gcloud API 만 사용 (GKE 생성 전)
#  promote : GKE 생성 후 클러스터 내부 일회성 Pod/Job 에서 Private IP 로 psql 실행
set -euo pipefail
PHASE="${1:?prepare | promote}"
INSTANCE="${CLOUDSQL_INSTANCE:-point-dr}"

case "$PHASE" in
  prepare)
    if [[ "${DRILL:-true}" == "true" ]]; then
      INSTANCE="${INSTANCE}-drill-$(date +%Y%m%d%H%M)"
      echo "[drill] clone → ${INSTANCE}"
      # TODO: gcloud sql instances clone point-dr "${INSTANCE}"
      # TODO: 이후 단계가 같은 인스턴스를 쓰도록 echo "CLOUDSQL_INSTANCE=${INSTANCE}" >> "$GITHUB_ENV"
    fi
    echo "TODO: prepare ${INSTANCE}"
    ;;
  promote)
    echo "[promote] ${INSTANCE}"
    # TODO: kubectl run/Job (postgres 클라이언트 이미지, Secret 은 External Secrets) 에서 Private IP 로 실행
    #   ALTER ROLE sink_writer NOLOGIN;
    #   ALTER ROLE app_rw LOGIN;
    #   \i scripts/dr/fix-sequences.sql
    #   \i scripts/dr/reconcile-wallet.sql
    echo "TODO: promote ${INSTANCE}"
    ;;
  *) echo "unknown phase: $PHASE" >&2; exit 2 ;;
esac
