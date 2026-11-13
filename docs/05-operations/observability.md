# 관측성 (Observability)

## 1. 스택

| 신호 | 수집 | 저장/조회 | 비고 |
|---|---|---|---|
| Metrics | Prometheus (kube-prometheus-stack), Micrometer | Grafana | AWS/GCP 동일 차트 → DR 환경도 같은 대시보드 |
| Logs | Fluent Bit | CloudWatch Logs (AWS) / Cloud Logging (GCP) | JSON 구조화 로그, traceId 포함 |
| Traces | OpenTelemetry SDK | (선택) Tempo / X-Ray | Phase 6 |
| 관리형 지표 | CloudWatch | Grafana CloudWatch datasource | RDS, MSK, ElastiCache |

## 2. SLO

| SLI | SLO | 측정 |
|---|---|---|
| monolith 가용성 | 99.9% / 30일 | 5xx 제외 성공 요청 비율 (ALB) |
| monolith p95 지연 | < 300ms | `http_server_requests_seconds` |
| event p95 지연 (피크) | < 500ms | 동일 |
| 원장 반영 지연 | 99% 이벤트가 60초 내 반영 | Kafka consumer lag(시간 환산) |
| CDC 복제 Lag (= RPO) | p99 ≤ 5초 | `dr_heartbeat` 기반 |

## 3. 핵심 대시보드

1. **Business** — 이벤트 참여 RPS, 당첨/낙첨/중복 비율, 지급 반영 지연
2. **Scaling** — HPA 레플리카, Karpenter 노드 수·Pending 파드·노드 준비 시간, Spot 비율
3. **Data** — RDS CPU/커넥션, Redis ops/s·메모리, Kafka consumer lag
4. **DR** — CDC Lag(초), Replication Slot 크기, VPN 터널 상태, Cloud SQL 쓰기량
5. **Cost** — 일별 비용 (Cost Explorer / Kubecost)

## 4. 알람

| 알람 | 조건 | 심각도 | 대응 |
|---|---|---|---|
| ALB 5xx 급증 | 5xx > 1% (5분) | P1 | [incident-response](runbooks/incident-response.md) |
| Route 53 Health Check 실패 | 3회 연속 | P1 | DR 판단 절차 진입 |
| CDC Lag 초과 | > 30초 (5분) | P1 | RPO 위반 위험 → 커넥터 점검 |
| Replication Slot 비대 | > 10GB | P2 | 커넥터 정지 여부 확인 |
| VPN 터널 Down | 1개 Down | P3 / 전부 Down P1 | |
| Kafka consumer lag | > 10만 건 | P2 | KEDA 확장 확인 |
| DLQ 유입 | > 0 | P3 | 원인 분석 후 재처리 |
| Karpenter Pending 파드 | 2분 이상 Pending | P2 | Spot 용량/서브넷 IP 확인 |
| 예산 | 월 예산 80% | P3 | FinOps 점검 |
