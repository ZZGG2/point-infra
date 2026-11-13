# 아키텍처 개요

## 1. 설계 원칙

1. **필요한 곳만 쪼갠다** — 트래픽 패턴이 다른 도메인만 MSA로 분리한다.
2. **평시 비용 ≒ 최소, 피크 성능 = 최대** — 확장은 초 단위, 축소는 0에 가깝게.
3. **DR은 "전부 복구"가 아니라 "비즈니스 생존"** — 돈(포인트)과 로그인부터 살린다.
4. **모든 것은 코드로** — 인프라는 Terraform, 워크로드는 Git(ArgoCD)이 진실의 원천.
5. **벤더 종속 최소화** — 컴퓨팅은 Kubernetes 표준, 데이터는 PostgreSQL 표준.

## 2. 전체 구성

```
[사용자]
   │
   ▼
Route 53 ── Failover Record (Primary: AWS ALB / Secondary: GCP Static IP)
   │
   ├────────────────────────── AWS ap-northeast-2 (Main) ─────────────────────────────┐
   │  ALB + AWS WAF (Bot 차단, Rate Limit)  ← Gateway API (AWS Load Balancer Controller)│
   │      ├─ /api/events/**  → event-service  (Karpenter NodePool: spot)              │
   │      ├─ /api/**         → monolith       (Managed NodeGroup: On-Demand)          │
   │      └─ /**             → web (SPA 정적, nginx)                                   │
   │                                                                                  │
   │  event-service ──▶ ElastiCache Valkey (대기열, 중복방지, 재고 카운터)                │
   │        └────────▶ MSK topic: point.reward.requested                              │
   │                         └──▶ monolith(point 모듈) consumer ──▶ RDS PostgreSQL    │
   │                                                                                  │
   │  RDS PostgreSQL ──▶ Debezium Source (MSK Connect) ──▶ MSK topic: cdc.*            │
   │                                     └──▶ JDBC Sink (MSK Connect) ──┐             │
   └──────────────────────────────────────────────────────────────────┼─────────────┘
                                                        HA VPN (IPsec, BGP)
   ┌──────────────────────── GCP asia-northeast3 (DR) ─────────────────┼─────────────┐
   │ [상시 - gcp-dr-standby]                                            ▼             │
   │   VPC, Cloud SQL for PostgreSQL (Private IP), Global Static IP,                  │
   │   Artifact Registry (이미지 이중 푸시), Secret Manager, GCS(Terraform State)       │
   │ [장애 시 - gcp-dr-compute]                                                        │
   │   GKE (Standard, Spot 미사용) → Helm으로 ArgoCD 설치 → ApplicationSet(gcp-dr)      │
   │   → monolith만 배포, /api/events/** 는 maintenance 응답                             │
   └──────────────────────────────────────────────────────────────────────────────────┘
```

## 3. 컴포넌트 책임

| 컴포넌트 | 책임 | 비고 |
|---|---|---|
| WAF (리전, ALB 연결) | 매크로/봇 차단, IP Rate Limit | 이벤트 1차 방어선. Terraform 이 Gateway ALB 에 연결 |
| ALB | 경로 기반 라우팅, TLS 종료(도메인·ACM 후) | Gateway API(Gateway, HTTPRoute)로 관리 |
| web | 프론트엔드 SPA 정적 서빙 (nginx, non-root) | DR 시 같은 이미지를 GKE 에 배포 |
| monolith | user / asset / point / cs 도메인 | 모듈 간 의존은 인터페이스로만 (향후 분리 대비) |
| event-service | 이벤트 참여, 대기열, 선착순 판정 | Stateless, Redis에 상태 위임 |
| Redis | 대기열, 중복 참여 방지, 선착순 카운터 | 원자 연산(Lua) |
| MSK | 이벤트 결과 비동기 전달, CDC 파이프라인 | 원장 반영 지연 허용 (최종 일관성) |
| RDS PostgreSQL | 원장(Source of Truth) | Multi-AZ, 논리 복제 활성화 |
| Debezium / JDBC Sink | AWS → GCP 실시간 복제 | 복제 Lag = RPO |
| Cloud SQL | DR 시 Primary DB로 승격 | 평시 쓰기 금지 (sink 전용 계정만) |
| Karpenter | 이벤트용 노드 프로비저닝 | Spot 우선, 다양한 인스턴스 타입 |
| KEDA | Cron 기반 사전 스케일 + Kafka Lag 기반 consumer 확장 | HPA 보완 |
| ArgoCD | 클러스터 상태를 Git과 동기화 | AWS/GCP 각 클러스터에 독립 설치 |

## 4. 요청 흐름

### 4.1 평시 — 포인트 잔액 조회
`Client → (WAF) ALB → monolith(point) → RDS → 응답` (화면은 `Client → ALB → web`)

### 4.2 이벤트 — 퀴즈 정답 포인트 지급
1. `POST /api/events/{id}/answers` → event-service
2. Redis `SADD event:{id}:participants` (Set) 로 중복 참여 차단 — 2~3단계와 당첨자 기록은 Lua 한 번으로 원자 처리 (ADR-0007)
3. Redis `DECR event:{id}:stock` ≥ 0 이면 당첨 (Lua로 원자 처리)
4. 당첨 시 Kafka `point.reward.requested` 발행 (key=userId, idempotencyKey=eventId:userId)
5. 클라이언트에는 즉시 "지급 예정" 응답 (202 Accepted)
6. monolith point consumer가 멱등키 유니크 제약으로 원장에 반영 → 잔액 갱신

### 4.3 DR — AWS 리전 장애
1. Route 53 Health Check 실패 감지 + 운영자 장애 선언
2. GitHub Actions `dr-failover` 워크플로 수동 승인 → `gcp-dr-compute` Terraform apply
3. GKE 생성 → Helm으로 ArgoCD 설치 → `gcp-dr` ApplicationSet 동기화 → monolith 배포
4. Cloud SQL 시퀀스 보정, sink 계정 비활성화, 앱 계정 쓰기 허용
5. Route 53 Secondary 레코드(GCP Static IP)로 트래픽 전환
   → 상세: [dr-runbook](../06-disaster-recovery/dr-runbook.md)

## 5. 관련 문서
- [hybrid-msa.md](hybrid-msa.md) · [network-design.md](network-design.md) · [data-architecture.md](data-architecture.md)
- [ADR 목록](../02-adr/README.md)
