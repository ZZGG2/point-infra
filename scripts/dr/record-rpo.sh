#!/usr/bin/env bash
# 장애 시 Cloud SQL 의 마지막 복제 시각 / 마지막 원장 시각 기록 (RPO 근거)
# Cloud SQL 은 Private IP 전용 → GKE 생성 후 클러스터 내부 일회성 Pod 에서 실행한다.
#
# 주의: 장애 후에는 now() - ts 가 "장애 발생 후 경과 시간" 이 되므로 RPO 가 아니다.
#   복제 지연(replication_lag = now() - ts)은 평시·드릴 모니터링 지표로만 쓴다.
#   실제 RPO = (Main 이 멈춘 시각) - last_replicated_at  ← Main 중단 시각은 사후에 AWS 기록으로 확정
set -euo pipefail
# TODO: kubectl run --rm -i rpo --image=<postgres client> -- psql ... -c "
#   SELECT ts AS last_replicated_at FROM public.dr_heartbeat;
#   SELECT max(created_at) AS last_ledger_at FROM point.point_ledger;" | tee -a "$GITHUB_STEP_SUMMARY"
echo "TODO: record last_replicated_at / last_ledger_at"
