#!/usr/bin/env bash
# usage: switch-dns.sh to-gcp | to-aws
# Primary 레코드의 Health Check 를 Inverted 로 바꿔 강제 실패 → Secondary(GCP) 로 전환 (ADR-0011)
set -euo pipefail
TARGET="${1:?to-gcp | to-aws}"
# TODO: aws route53 update-health-check --health-check-id "$HC_ID" --inverted (to-gcp) / --no-inverted (to-aws)
# 주의: Route 53 컨트롤 플레인 장애 시 → 도메인 등록기관에서 NS 변경 절차 (dr-runbook §2-8)
echo "TODO: switch DNS ${TARGET}"
