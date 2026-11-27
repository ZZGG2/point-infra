# DR 복제 (AWS RDS for PostgreSQL → GCP Cloud SQL)

PostgreSQL 네이티브 논리 복제(pgoutput). RDS 가 발행하고 Cloud SQL 이 HA VPN 을 통해 RDS 에 접속해 받는다.

```
RDS (PUBLICATION dr_publication, slot dr_subscription) ◀── 접속·수신 (HA VPN) ── Cloud SQL (SUBSCRIPTION dr_subscription)
```

| 파일 | 실행 위치 | 설명 |
|---|---|---|
| `publication.sql` | RDS | 복제 계정(`dr_replicator`), Publication(복제 대상 테이블만), pg_cron heartbeat |
| `subscription.sql` | Cloud SQL | Subscription (초기 복사 후 변경분 수신) |

- 순서: Flyway 양쪽 적용 → `publication.sql` → `subscription.sql`
- 트랜잭션 단위·커밋 순서로 적용된다 → 원장과 지갑이 같은 트랜잭션 경계에서 끊긴다
- 스키마(DDL)와 시퀀스는 복제되지 않는다 → Flyway 를 Cloud SQL 에도 적용, 승격 시 `scripts/dr/fix-sequences.sql`
- slot 이 WAL 을 붙잡는다 → RDS `max_slot_wal_keep_size` 상한 + `OldestReplicationSlotLag`·디스크 알람 ([observability](../docs/05-operations/observability.md))
- 설계 근거: [ADR-0020](../docs/02-adr/0020-postgresql-logical-replication.md), [ADR-0013](../docs/02-adr/0013-rds-postgresql.md), [data-architecture §4](../docs/01-architecture/data-architecture.md)

## 복제 지연 vs RPO (Cloud SQL 에서 측정)

RDS 의 pg_cron 이 1초마다 `public.dr_heartbeat.ts` 를 갱신하고, 이 행이 다른 테이블과 같은 경로로 Cloud SQL 에 복제된다.

| 언제 | 쿼리 | 의미 |
|---|---|---|
| 평상시 · DR 드릴 (Main 정상) | `SELECT now() - ts AS replication_lag FROM public.dr_heartbeat;` | **복제 지연**. 지금 장애가 나면 잃을 수 있는 최대 폭의 근사치 → 알람·대시보드 지표 |
| 실제 장애 후 (Main 중단) | `SELECT ts AS last_replicated_at FROM public.dr_heartbeat;`<br>`SELECT max(created_at) AS last_ledger_at FROM point.point_ledger;` | **마지막 복제 시각**과 **마지막 원장 시각**을 기록한다. 장애 후에는 `now() - ts` 가 "장애 발생 후 경과 시간" 이 되므로 RPO 로 쓰면 안 된다 |

- 실제 RPO = (Main 이 멈춘 시각) − `last_replicated_at`. Main 이 멈춘 시각은 CloudWatch/ALB 마지막 정상 응답 등 AWS 쪽 기록으로 사후 확정한다.
- 보조 지표: RDS `pg_stat_replication`(write/flush/replay lag)·`pg_replication_slots`, Cloud SQL `pg_stat_subscription`(`last_msg_receipt_time`)
- Cloud SQL 은 Private IP 전용이므로 위 쿼리는 GCP VPC 내부(GKE 의 일회성 Pod/Job)에서 실행한다 → [dr-runbook](../docs/06-disaster-recovery/dr-runbook.md)
