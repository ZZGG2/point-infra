# CDC (AWS RDS for PostgreSQL → GCP Cloud SQL)

```
RDS (PostgreSQL) ──pgoutput──▶ Debezium Source ──▶ MSK (cdc.*) ──▶ Debezium JDBC Sink ──HA VPN──▶ Cloud SQL
```

| 파일 | 설명 |
|---|---|
| `publication.sql` | RDS 복제 계정 / Publication (복제 대상 테이블만) |
| `debezium-source-rds.json` | Source 커넥터 (heartbeat 로 복제 지연 측정) |
| `jdbc-sink-cloudsql.json` | Sink 커넥터 (upsert, delete 반영) |

- 배포: MSK Connect 커스텀 플러그인 + 커넥터 (`infra/terraform/modules/aws/msk`)
- 스키마(DDL)는 복제되지 않는다 → Flyway 를 Cloud SQL 에도 적용
- 설계 근거: [ADR-0005](../docs/02-adr/0005-cdc-debezium-replication.md), [ADR-0013](../docs/02-adr/0013-rds-postgresql.md), [data-architecture §4](../docs/01-architecture/data-architecture.md)

## 복제 지연 vs RPO (Cloud SQL 에서 측정)

Source 커넥터가 1초마다 `public.dr_heartbeat.ts` 를 갱신하고, 이 행이 다른 테이블과 같은 경로로 Cloud SQL 에 복제된다.

| 언제 | 쿼리 | 의미 |
|---|---|---|
| 평상시 · DR 드릴 (Main 정상) | `SELECT now() - ts AS replication_lag FROM public.dr_heartbeat;` | **복제 지연**. 지금 장애가 나면 잃을 수 있는 최대 폭의 근사치 → 알람·대시보드 지표 |
| 실제 장애 후 (Main 중단) | `SELECT ts AS last_replicated_at FROM public.dr_heartbeat;`<br>`SELECT max(created_at) AS last_ledger_at FROM point.point_ledger;` | **마지막 복제 시각**과 **마지막 원장 시각**을 기록한다. 장애 후에는 `now() - ts` 가 "장애 발생 후 경과 시간" 이 되므로 RPO 로 쓰면 안 된다 |

- 실제 RPO = (Main 이 멈춘 시각) − `last_replicated_at`. Main 이 멈춘 시각은 CloudWatch/ALB 마지막 정상 응답 등 AWS 쪽 기록으로 사후 확정한다.
- Cloud SQL 은 Private IP 전용이므로 위 쿼리는 GCP VPC 내부(GKE 의 일회성 Pod/Job)에서 실행한다 → [dr-runbook](../docs/06-disaster-recovery/dr-runbook.md)
