#!/usr/bin/env bash
# Cloud SQL 의 마지막 heartbeat 시각 → 실제 RPO 기록
set -euo pipefail
# TODO: psql -c "SELECT ts, now() - ts AS lag FROM public.dr_heartbeat" | tee -a "$GITHUB_STEP_SUMMARY"
echo "TODO: record RPO"
