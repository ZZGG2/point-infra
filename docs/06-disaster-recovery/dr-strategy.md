# 재해복구(DR) 전략

## 1. 목표

| 지표 | 목표 | 정의 |
|---|---|---|
| **RTO** | ≤ 30분 | 장애 선언(승인) 시점 → GCP에서 로그인/잔액조회 정상 응답 |
| **RPO** | ≤ 5초 (p99) | 장애 시점 기준 Cloud SQL 미반영 커밋의 시간 폭 |
| 복구 범위 | user, asset, point, cs | event는 점검 처리 (선택적 복구) |

## 2. 재해 유형별 대응

| 재해 | 범위 | 대응 | DR 가동 |
|---|---|---|---|
| 단일 파드/노드 장애 | 서비스 일부 | K8s 자가 복구 | ❌ |
| 단일 AZ 장애 | AZ | Multi-AZ (EKS 노드, RDS, Redis — 원장 반영 Stream 이 있어 자동 장애 조치 필수, ADR-0019) | ❌ |
| RDS Primary 장애 | DB | RDS Multi-AZ 자동 Failover (Standby 승격) | ❌ |
| **리전 장애 / AWS 사업자 장애** | 전체 | **GCP Pilot Light 가동** | ✅ |
| 데이터 논리 오류 (잘못된 DELETE) | 데이터 | RDS PITR (논리 복제로 오류도 복제되므로 DR은 해답 아님) | ❌ |
| 랜섬웨어 / 계정 탈취 | 계정 | 별도 계정 백업, 불변 백업 (확장 과제) | 상황별 |

> 마지막 두 행이 중요: **복제는 백업이 아니다.** 논리 오류는 그대로 DR로 복제된다.

## 3. Pilot Light 구성

```
          평시                                   DR 가동 후
 ┌─ GCP ───────────────────┐          ┌─ GCP ─────────────────────────────┐
 │ VPC / Subnet       ●    │          │ VPC / Subnet                ●     │
 │ HA VPN             ●    │          │ HA VPN (AWS 측 Down)        ○     │
 │ Cloud SQL (구독)   ●    │   ──▶    │ Cloud SQL (Primary 승격)    ●     │
 │ Static IP          ●    │          │ Static IP → GKE Gateway     ●     │
 │ Artifact Registry  ●    │          │ GKE + ArgoCD                ●     │
 │ Secret Manager     ●    │          │ core-service (2~3 replicas) ●     │
 │ GKE                ✕    │          │ event-service               ✕     │
 └─────────────────────────┘          └───────────────────────────────────┘
```

### 프론트엔드 (web 파드)
- point-frontend CI가 web 이미지를 **ECR과 Artifact Registry에 동시 푸시** → DR 시 GKE 에 core-service 와 함께 같은 이미지로 배포.
- 경로 규칙(HTTPRoute)은 AWS·GCP 동일, GatewayClass 만 다르다 (AWS: `gateway.k8s.aws/alb`, GCP: `gke-l7-global-external-managed`).

## 4. RTO 예산 (30분 분해)

| 단계 | 작업 | 목표 시간 | 누적 |
|---|---|---|---|
| T0 | 알람 → 온콜 판단 → 장애 선언 & 워크플로 승인 | 5분 | 5분 |
| T1 | Cloud SQL 준비 (gcloud API — 드릴이면 클론) | 1분 | 6분 |
| T2 | `gcp-dr-compute` Terraform apply (GKE + 노드풀) | 10~11분 | 17분 |
| T3 | ArgoCD Helm 설치 + root App 동기화 | 3분 | 20분 |
| T4 | 클러스터 내부 Job: RPO 근거 기록, Cloud SQL 승격 (구독 해제, 계정 전환, 시퀀스·지갑 잔액 보정) | 2분 | 22분 |
| T5 | External Secrets 동기화, core-service Ready | 3분 | 25분 |
| T6 | Route 53 전환 + DNS 전파 (TTL 60s) | 2분 | 27분 |
| T7 | 스모크 테스트 (로그인, 잔액 조회) | 2분 | **29분** |

> Cloud SQL 은 Private IP 전용 → GitHub runner 에서 SQL 을 실행할 수 없으므로 DB 작업(T4)은 GKE 생성(T2) 이후 클러스터 내부에서 수행한다. DNS 전환 방식은 [dr-runbook §4](dr-runbook.md), ADR-0016(Proposed).

**RTO 단축 옵션 (트레이드오프 문서화용):**
| 옵션 | 효과 | 비용 |
|---|---|---|
| GKE 컨트롤 플레인만 상시 유지 (노드 0) | T2를 ~3분으로 단축 → RTO ~20분 | GKE 클러스터 관리 수수료 상시 발생 |
| GKE Autopilot | 노드 관리 불필요 | 파드 단위 과금, 세밀한 제어 감소 |

## 5. 데이터 정합성 처리

| 이슈 | 처리 |
|---|---|
| 장애 시점 미복제 데이터 (≤ RPO) | Failback 시 RDS WAL/로그와 비교해 누락분 식별·보정 |
| 시퀀스 | `scripts/dr/fix-sequences.sql` 로 `max(id) + 100000` 보정 |
| 원장 ↔ 지갑 잔액 불일치 | 논리 복제는 트랜잭션 단위로 적용하므로 정상이면 생기지 않는다. 안전장치로 `scripts/dr/reconcile-wallet.sql` 을 유지해 지갑을 사용자별 마지막 `balance_after` 에 맞추고, 불일치 내역은 Failback 대사 자료로 보관 (ADR-0020) |
| AWS Redis Stream 에 있었으나 미반영된 reward (퀴즈·출석) | Stream 은 GCP 로 복제되지 않는다 → DR 중에는 처리 불가, Failback 후 consumer 재개로 자동 반영 (멱등, ADR-0019) |
| 퀴즈 이벤트 지급 (ADR-0018 즉시 지급) | 피크 중 재해면 **일부 당첨자만 지급된 상태**로 DR 운영 (판정 기준 없음). DB 에 반영된 지급은 유지, 미반영분만 Failback 후 Stream 잔여 항목으로 지급 (멱등). RDS 에만 커밋된 원장(복제 지연분)은 **consumer group 위치 되감기**(`XGROUP SETID`)로 다시 채운다 ([runbook §5](dr-runbook.md#5-failback-절차-계획된-점검) 6-1). Stream 보존(7일)을 넘긴 DR·ElastiCache 소실·AWS 영구 소실이면 미지급 명단 복원 불가 → 재진행/일괄 보상 (비즈니스 결정) |
| Redis 당첨 기록·Stream | 당첨자 Set 과 Stream 이 같은 ElastiCache 에 있다 → Redis 가 살아 있으면 Failback 후 Set ↔ 원장 대사. ElastiCache 까지 소실되면 미반영 당첨 명단은 복원할 수 없다 (ADR-0019) |

## 6. Failback 원칙
- Failback은 **긴급하지 않다.** 계획된 점검 시간에 수행한다.
- 방향을 뒤집은 논리 복제(Cloud SQL PUBLICATION → RDS SUBSCRIPTION) 또는 덤프/복원으로 RDS를 최신화한 뒤 전환. RDS 에만 커밋된 행이 있으면 역방향 apply 가 고유키 충돌로 멈추므로 먼저 따로 빼 둔다 (ADR-0020).
- 상세: [dr-runbook.md §3](dr-runbook.md)
