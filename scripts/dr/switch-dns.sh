#!/usr/bin/env bash
# usage: switch-dns.sh to-gcp | to-aws
# Primary 레코드의 Health Check 를 Inverted 로 바꿔 강제 실패 → Secondary(GCP) 로 전환 (ADR-0011)
set -euo pipefail
TARGET="${1:?to-gcp | to-aws}"
# TODO: aws route53 update-health-check --health-check-id "$HC_ID" --inverted (to-gcp) / --no-inverted (to-aws)
# 주의: 이 방식은 AWS API(자격 증명 + Route 53 컨트롤 플레인)가 필요하다 → ADR-0010 과 충돌.
#       AWS 비의존 전환 방안은 ADR-0016 (Proposed) / dr-runbook §4 참고. 등록기관 NS 변경은 TLD TTL 때문에 RTO 내 불가.
echo "TODO: switch DNS ${TARGET}"
