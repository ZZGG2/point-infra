# 데이터 아키텍처

## 1. 데이터 저장소

| 저장소 | 엔진 | 용도 | DR 복제 |
|---|---|---|---|
| RDS for PostgreSQL | 16.x (Multi-AZ) | monolith 전 도메인 (Source of Truth) | ✅ 핵심 테이블만 |
| ElastiCache | Valkey 7.2, Primary + Replica (Cluster mode 비활성) | 이벤트 대기열, 중복 방지, 카운터 | ❌ (휘발성, DR 시 이벤트 닫음) |
| MSK | Kafka 3.x | 이벤트 → 원장, CDC 파이프라인 | ❌ (CDC 경유) |
| S3 | - | 로그 아카이브, 백업 | 선택 (Cross-cloud 불필요) |

## 2. 스키마 개요 (monolith)

| 스키마/테이블 | 설명 | CDC 복제 |
|---|---|---|
| `users.app_user` | 사용자 계정 (`user`는 예약어) | ✅ |
| `users.user_credential` | 비밀번호 해시 | ✅ |
| `asset.linked_account` | 마이데이터 연동 계좌 (Mock) | ✅ |
| `point.point_wallet` | 사용자별 잔액 | ✅ |
| `point.point_ledger` | 포인트 원장 (append-only) | ✅ |
| `point.refund_request` | 환불 요청 | ✅ |
| `cs.notice`, `cs.inquiry` | 고객센터 | ❌ (DR 시 읽기 불필요, 사후 복구) |
| `asset.asset_snapshot` | 자산 조회 캐시 | ❌ (재조회 가능) |

**원칙:** "잃으면 돈/신뢰 문제가 생기는 데이터"만 실시간 복제한다. 재생성 가능한 데이터는 제외해 Lag과 비용을 줄인다.

## 3. Kafka 토픽 설계

| 토픽 | Key | 파티션 | 보존 | Producer → Consumer |
|---|---|---|---|---|
| `point.reward.requested` | userId | 12 | 7일 | event-service → monolith(point) |
| `point.reward.dlq` | userId | 3 | 14일 | point consumer (실패 건) |
| `cdc.users.*`, `cdc.point.*`, `cdc.asset.linked_account` | PK | 6 | 3일 | Debezium → JDBC Sink |
| `connect-configs/offsets/status` | - | - | compact | MSK Connect 내부 |

- `userId` 키 → 동일 사용자 이벤트의 순서 보장.
- 파티션 수 = 피크 시 consumer 최대 레플리카 수 상한 (KEDA maxReplicaCount와 맞춤).

## 4. CDC 파이프라인

```
RDS for PostgreSQL (wal_level=logical, rds.logical_replication=1)
  └─ Replication Slot: debezium_slot / Publication: dr_publication (복제 대상 테이블만)
       └─ Debezium PostgreSQL Connector (MSK Connect, pgoutput 플러그인)
            └─ MSK topics: cdc.<schema>.<table>
                 └─ Debezium JDBC Sink Connector (MSK Connect, upsert + delete 처리)
                      └─ (HA VPN) Cloud SQL for PostgreSQL (Private IP)
```

### 주의사항 (설계 시 반드시 고려)
| 이슈 | 대응 |
|---|---|
| DDL은 CDC로 복제되지 않음 | Flyway 마이그레이션을 **AWS·GCP 양쪽에 적용**하는 CI 단계 추가 |
| 시퀀스 값은 복제되지 않음 | Failover 시 `setval(max(id)+버퍼)` 스크립트 실행 |
| Replication Slot 미소비 시 WAL 누적 → RDS 스토리지 증가 (max_allocated_storage 자동 확장) | `OldestReplicationSlotLag` 알람 |
| Sink가 쓰는 Cloud SQL에 앱이 쓰면 충돌 | 평시 앱 계정 쓰기 권한 없음, sink 전용 계정만 |
| 초기 데이터 적재 | Debezium `snapshot.mode=initial` |

## 5. RPO 정의

- **RPO = 장애 시점에 RDS에 커밋되었으나 Cloud SQL에 반영되지 않은 데이터의 시간 폭**
- 측정: RDS의 `commit_ts` vs Cloud SQL 반영 시각 (heartbeat 테이블 사용)
  - Debezium `heartbeat.action.query`로 1초마다 `dr_heartbeat` 갱신 → Cloud SQL에서 `now() - max(ts)` = 복제 Lag
- 목표: **Lag p99 ≤ 5초** → "RPO near-zero" 근거로 대시보드 캡처 제출
- RPO가 0이 아닌 이유: 비동기 복제. 동기 복제는 클라우드 간 RTT(수십 ms)가 모든 커밋에 더해져 원장 쓰기 성능을 희생하므로 채택하지 않음. → [ADR-0005](../02-adr/0005-cdc-debezium-replication.md)

## 6. 백업

| 대상 | 방식 | 보존 |
|---|---|---|
| RDS | 자동 백업 + PITR | 7일 (운영 권장 35일) |
| RDS | 일 1회 스냅샷 | 30일 |
| Cloud SQL | 자동 백업 | 7일 |
| Terraform State | S3/GCS 버전 관리 | 무기한 |
