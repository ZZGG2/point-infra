# CDC (AWS Aurora → GCP Cloud SQL)

```
Aurora ──pgoutput──▶ Debezium Source ──▶ MSK (cdc.*) ──▶ Debezium JDBC Sink ──HA VPN──▶ Cloud SQL
```

| 파일 | 설명 |
|---|---|
| `publication.sql` | Aurora 복제 계정 / Publication (복제 대상 테이블만) |
| `debezium-source-aurora.json` | Source 커넥터 (heartbeat 로 RPO 측정) |
| `jdbc-sink-cloudsql.json` | Sink 커넥터 (upsert, delete 반영) |

- 배포: MSK Connect 커스텀 플러그인 + 커넥터 (`infra/terraform/modules/aws/msk`)
- 스키마(DDL)는 복제되지 않는다 → Flyway 를 Cloud SQL 에도 적용
- RPO 측정 (Cloud SQL): `SELECT now() - ts AS replication_lag FROM public.dr_heartbeat;`
- 설계 근거: [ADR-0005](../docs/02-adr/0005-cdc-debezium-replication.md), [data-architecture §4](../docs/01-architecture/data-architecture.md)
