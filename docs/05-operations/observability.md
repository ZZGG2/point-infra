# 관측성 (Observability)

## 1. 스택

| 신호 | 수집 | 저장/조회 | 비고 |
|---|---|---|---|
| Metrics | Prometheus (kube-prometheus-stack), Micrometer | Grafana | AWS/GCP 동일 차트 → DR 환경도 같은 대시보드 |
| Logs | Fluent Bit | CloudWatch Logs (AWS) / Cloud Logging (GCP) | JSON 구조화 로그, traceId 포함 |
| Traces | OpenTelemetry SDK | (선택) Tempo / X-Ray | Phase 6 |
| 관리형 지표 | CloudWatch | Grafana CloudWatch datasource | RDS (`OldestReplicationSlotLag`, `TransactionLogsDiskUsage` 포함), ElastiCache |

> 현재 구현: point-backend 가 `/actuator/prometheus`(Micrometer)를 노출하는 것까지. kube-prometheus-stack·Fluent Bit·대시보드·알람 매니페스트는 아직 없다. p95 계산에는 `management.metrics.distribution.percentiles-histogram.http.server.requests=true` 가 필요하다 (환경 변수로는 `MANAGEMENT_METRICS_DISTRIBUTION_PERCENTILESHISTOGRAM_HTTP_SERVER_REQUESTS=true` — 하이픈은 빼고 쓴다).

## 2. SLO

| SLI | SLO | 측정 |
|---|---|---|
| core-service 가용성 | 99.9% / 30일 | 5xx 제외 성공 요청 비율 (ALB) |
| core-service p95 지연 | < 300ms | `http_server_requests_seconds` |
| event p95 지연 (피크) | < 500ms | 동일 |
| 원장 반영 지연 | 99% 이벤트가 60초 내 반영 | Stream 의 가장 오래된 미처리 항목 나이 (`XPENDING` / consumer group lag, Stream ID 의 타임스탬프로 시간 환산) |
| DR 복제 Lag (= RPO) | p99 ≤ 5초 | `dr_heartbeat` 기반 (RDS pg_cron 이 1초마다 갱신) |

## 3. 핵심 대시보드

1. **Business** — 이벤트 참여 RPS, 당첨/낙첨/중복 비율, 지급 반영 지연
2. **Scaling** — HPA 레플리카, Karpenter 노드 수·Pending 파드·노드 준비 시간, Spot 비율
3. **Data** — RDS CPU/커넥션, Redis ops/s·메모리(보상 Stream 보존분 포함), Stream pending·길이, DLQ(`reward:dlq`) 길이
4. **DR** — CDC Lag(초), Replication Slot 크기, VPN 터널 상태, Cloud SQL 쓰기량
5. **Cost** — 일별 비용 (Cost Explorer / Kubecost)

## 4. 알람

| 알람 | 조건 | 심각도 | 대응 |
|---|---|---|---|
| ALB 5xx 급증 | 5xx > 1% (5분) | P1 | [incident-response](runbooks/incident-response.md) |
| Route 53 Health Check 실패 | 3회 연속 | P1 | DR 판단 절차 진입 |
| 복제 Lag 초과 | > 30초 (5분) | P1 | RPO 위반 위험 → 구독 상태(`pg_stat_subscription`)·VPN 점검 |
| Replication Slot 비대 | > 10GB (`max_slot_wal_keep_size` 보다 낮게) | P2 | 구독 정지 여부 확인. 상한을 넘으면 slot 이 무효화돼 재동기화 필요 |
| VPN 터널 Down | 1개 Down | P3 / 전부 Down P1 | |
| 보상 Stream pending | > 10만 건 | P2 | KEDA 확장 확인 |
| DLQ(`reward:dlq`) 유입 | > 0 | P3 | 원인 분석 후 재처리 |
| ElastiCache 메모리 | > 75% | P2 | Stream 보존(`XTRIM MINID`) 동작·이벤트 규모 확인. 가득 차면 판정·기록이 모두 막힌다 |
| Karpenter Pending 파드 | 2분 이상 Pending | P2 | Spot 용량/서브넷 IP 확인 |
| 예산 | 월 예산 80% | P3 | FinOps 점검 |
