# 테스트 전략

## 1. 테스트 피라미드

| 레벨 | 도구 | 대상 | 실행 |
|---|---|---|---|
| Unit | JUnit 5 | 도메인 로직 (원장 계산, 판정) | PR |
| Architecture | ArchUnit | 모놀리스 모듈 경계 | PR |
| Integration | Testcontainers (PostgreSQL, Redis, Kafka) | 멱등 소비, Lua 스크립트 | PR |
| IaC | tflint, checkov, terraform validate | Terraform | PR |
| Load | k6 | 이벤트 폭주 | 수동 / 릴리스 전 |
| Chaos | AWS FIS, kubectl (노드/파드 종료) | 복원력 | 월 1회 |
| DR | dr-failover 워크플로 | RTO/RPO | [dr-drill-plan](../06-disaster-recovery/dr-drill-plan.md) |

## 2. 부하 테스트 시나리오 (k6)

| 시나리오 | 패턴 | 목표 | 검증 포인트 |
|---|---|---|---|
| S1 Baseline | monolith 100 RPS 30분 | p95 < 300ms | 평시 기준선 |
| S2 Spike | event 0 → 5,000 RPS (10초 내) 5분 유지 | p95 < 500ms, 에러 < 0.1% | KEDA 사전 확장 有/無 비교 |
| S3 Duplicate | 동일 사용자 동시 10회 제출 | 지급 1회 | Redis 원자성 + 원장 멱등 |
| S4 Stock | 당첨 1,000명, 참여 50,000명 | 정확히 1,000건 지급 | 초과 지급 0 |
| S5 Isolation | S2 실행 중 monolith 지연 측정 | monolith p95 변화 < 10% | 장애/부하 격리 |
| S6 Spot 회수 | S2 중 Spot 노드 강제 종료 | 에러율 < 1% | PDB, 재스케줄 |

### 비교 실험 (포트폴리오 핵심 그래프)
| 실험 | A | B | 측정 |
|---|---|---|---|
| 사전 확장 효과 | HPA만 | KEDA Cron + HPA | 첫 30초 에러율·지연 |
| 노드 확장 속도 | Cluster Autoscaler | Karpenter | Pending → Running 시간 |
| 격리 효과 | 전체 모놀리스 (event 포함) | 하이브리드 | monolith p95 |

## 3. 결과 기록 위치
`load-test/results/YYYYMMDD-<scenario>.md` + Grafana 스냅샷
