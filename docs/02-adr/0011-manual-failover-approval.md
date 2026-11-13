# ADR-0011: 자동 Failover 대신 승인 기반 Failover
- 상태: Accepted · 날짜: 2026-11-05

## 결정
감지는 자동(Route 53 Health Check, CloudWatch 알람), **전환 실행은 사람의 승인 1회** 후 파이프라인이 자동 수행한다.

## 이유
- Pilot Light 전환은 **DB Primary 변경**을 동반한다. 일시적 네트워크 문제로 오탐 Failover 시, AWS가 살아나면서 **양쪽 DB에 쓰기가 발생(Split-brain)** → 원장 불일치.
- 금융권 DR 실무도 "장애 선언 → 전환 결정" 단계를 둔다.
- RTO 30분 중 승인 대기 목표: 5분 이내 (온콜 알림 → 판단 → 승인)

## 구현
- GitHub Actions `environment: dr-production` + Required reviewers
- 승인 이후 단계는 전부 자동 (사람이 콘솔에서 작업하는 단계 0개)
