# 데이터 아키텍처

## 1. 데이터 저장소

| 저장소 | 엔진 | 용도 | DR 복제 |
|---|---|---|---|
| RDS for PostgreSQL | 16.x (Multi-AZ) | core-service 전 도메인 (Source of Truth) | ✅ 핵심 테이블만 |
| ElastiCache | Valkey 7.2, Primary + Replica, **Multi-AZ + 자동 장애 조치 필수** (Cluster mode 비활성) | 이벤트 대기열, 중복 방지, 카운터, **당첨·출석 보상 Stream (원장 반영 버퍼, ADR-0019)** | ❌ (DR 시 이벤트 닫음. 미반영 Stream 항목은 Failback 후 반영) |
| S3 | - | 로그 아카이브, 백업 | 선택 (Cross-cloud 불필요) |

## 2. 스키마 개요 (core-service)

| 스키마/테이블 | 설명 | DR 복제 |
|---|---|---|
| `users.app_user` | 사용자 계정 (`user`는 예약어) | ✅ |
| `users.user_credential` | 비밀번호 해시 | ✅ |
| `users.refresh_token` | 로그인 세션 (refresh token **SHA-256 해시**, 만료·폐기 시각) | ❌ (Failover 후 재로그인, 자격 증명은 복제됨) |
| `asset.linked_account` | 마이데이터 연동 계좌 (Mock) | ✅ |
| `point.point_wallet` | 사용자별 잔액 | ✅ |
| `point.point_ledger` | 포인트 원장 (append-only) | ✅ |
| `point.refund_request` | 환불 요청 | ✅ |
| `point.reward_pending`, `point.event_settlement` | ADR-0017 일괄 정산용 — **ADR-0018(즉시 지급) 이후 미사용** (Flyway 이력 때문에 테이블만 남음, 빈 채) | ❌ (복제 대상 아님 — `dr_publication` 에서 제외) |
| `cs.notice` | 공지 | ❌ (DR 시 읽기 불필요, 사후 복구) |
| `public.dr_heartbeat` | 복제 지연(RPO) 측정 — RDS pg_cron 이 1초마다 갱신 | ✅ |
| `cs.inquiry` *(계획, 미생성)* | 1:1 문의 | ❌ |
| `asset.asset_snapshot` *(계획, 미생성)* | 자산 조회 캐시 | ❌ (재조회 가능) |

> 실제 테이블은 point-backend `core-service/src/main/resources/db/migration` (Flyway) 기준. *(계획)* 표시는 아직 마이그레이션이 없다.

**원칙:** "잃으면 돈/신뢰 문제가 생기는 데이터"만 실시간 복제한다. 재생성 가능한 데이터는 제외해 Lag과 비용을 줄인다.

## 3. 원장 반영 Redis Stream 설계 (ADR-0019)

| 키 | 타입 | 내용 | Producer → Consumer | 보존 |
|---|---|---|---|---|
| `event:{id}:rewards` | Stream | 퀴즈 당첨 (당첨 건만) | event-service `claim_reward.lua` 가 판정과 같은 스크립트에서 `XADD` → core-service consumer group `point-ledger` | 7일 (`XTRIM MINID`) |
| `attendance:{yyyyMMdd}:rewards` | Stream | 출석 보상 | 출석 스크립트가 `SETBIT` 와 같은 스크립트에서 `XADD` → core-service `point-ledger` | 7일 |
| `reward:streams` | Set | 열린 퀴즈 Stream 이름 등록 (core-service 가 읽을 목록) | 이벤트 오픈 시 등록 | 이벤트 종료·보존 기간 후 정리 |
| `reward:dlq` | Stream | 전달 횟수 초과(예: 5) 또는 비재시도 오류 건 | core-service → 운영자 재처리 | 처리 후 정리 |

- 메시지 필드: `idempotencyKey`, `userId`, `eventId`, `amount`, `reason`, `occurredAt` (스키마 `point-backend/api/events/point.reward.requested.schema.json` 재사용)
- 소비: `XREADGROUP` → 반영 성공 시 `XACK`. 반영이 멱등(`idempotency_key` UNIQUE)이라 at-least-once 로 충분하다.
- 재시도: 처리 안 된 항목(PEL)은 min-idle(기본 60초)이 지나면 다른 파드가 가져간다. 구현은 `XPENDING` + `XCLAIM` (`XAUTOCLAIM` 과 같은 동작 — Spring Data Redis 에 `XAUTOCLAIM` 이 없음). 설정: `app.reward-stream.min-idle`, `max-deliveries`(기본 5)
- `XACK` 된 항목도 보존 기간까지 남긴다 → Failback 때 consumer group 위치를 되감아(`XGROUP SETID`) 다시 반영하는 근거 ([dr-runbook](../06-disaster-recovery/dr-runbook.md))
- 사용자별 순서는 Stream 이 보장하지 않는다. 같은 사용자의 반영은 지갑 행 잠금으로 직렬화된다 ([domain-model §3](../03-development/domain-model.md)).
- Redis 장애 조치(비동기 복제) 시 마지막 쓰기가 유실될 수 있다 → 필요하면 스크립트 뒤 `WAIT 1 <ms>` (지연과 맞교환, 구현 시 측정)

## 4. DR 복제 (PostgreSQL 논리 복제, ADR-0020)

```
RDS for PostgreSQL (rds.logical_replication=1, max_slot_wal_keep_size, pg_cron)
  └─ Publication: dr_publication (복제 대상 테이블만) / Replication Slot: dr_subscription
       ▲ 접속·수신 (pgoutput, 계정 dr_replicator) — HA VPN, Cloud SQL 대역 10.30.0.0/20 → RDS 5432
  Cloud SQL for PostgreSQL (Private IP)
  └─ Subscription: dr_subscription (copy_data=true 로 초기 복사 후 변경분 적용)
```
- 설정 SQL: [`cdc/publication.sql`](../../cdc/publication.sql) (RDS), [`cdc/subscription.sql`](../../cdc/subscription.sql) (Cloud SQL)

### 주의사항 (설계 시 반드시 고려)
| 이슈 | 대응 |
|---|---|
| DDL은 복제되지 않음 | Flyway 마이그레이션을 **AWS·GCP 양쪽에 적용**하는 CI 단계 추가. 테이블 추가 시 `ALTER PUBLICATION … ADD TABLE` + `ALTER SUBSCRIPTION … REFRESH PUBLICATION` |
| 시퀀스 값은 복제되지 않음 | Failover 시 `setval(max(id)+버퍼)` 스크립트 실행 |
| 트랜잭션 단위·커밋 순서로 적용 → 원장·지갑이 같은 트랜잭션 경계에서 끊긴다 | `scripts/dr/reconcile-wallet.sql` 은 안전장치로 유지 (드릴에서 drift 0 이 반복 확인되면 재검토) |
| 구독이 끊기면 slot 이 WAL 을 붙잡아 RDS 스토리지 증가 | `max_slot_wal_keep_size` 상한 + `OldestReplicationSlotLag`·`TransactionLogsDiskUsage` 알람. 상한을 넘으면 slot 무효화 → 구독 재생성 + 초기 복사 |
| 구독이 쓰는 Cloud SQL에 앱이 쓰면 충돌 | 평시 앱 계정(`app_rw`) NOLOGIN. 승격 때 구독을 해제한 뒤 활성화 |
| 초기 데이터 적재 | `CREATE SUBSCRIPTION … WITH (copy_data = true)` |
| Failover 시 구독 해제 | AWS 가 응답하지 않으면 `DROP SUBSCRIPTION` 이 멈춘다 → `DISABLE` → `SET (slot_name = NONE)` → `DROP`. RDS 의 slot 은 AWS 복구 후 정리 |

## 5. RPO 정의

- **RPO = 장애 시점에 RDS에 커밋되었으나 Cloud SQL에 반영되지 않은 데이터의 시간 폭**
- 측정: RDS의 `commit_ts` vs Cloud SQL 반영 시각 (heartbeat 테이블 사용)
  - RDS `pg_cron` 이 1초마다 `dr_heartbeat` 갱신 → 평시·드릴: Cloud SQL에서 `now() - ts` = **복제 Lag** (모니터링 지표)
  - 실제 장애 후에는 `now() - ts` 가 "장애 후 경과 시간" 이 되므로 RPO 로 쓰지 않는다 → `ts`(마지막 복제 시각)와 `max(point_ledger.created_at)`(마지막 원장 시각)를 기록하고, RPO = Main 중단 시각 − 마지막 복제 시각 ([cdc/README](../../cdc/README.md))
- 목표: **Lag p99 ≤ 5초** → "RPO near-zero" 근거로 대시보드 캡처 제출
- RPO가 0이 아닌 이유: 비동기 복제. 동기 복제는 클라우드 간 RTT(수십 ms)가 모든 커밋에 더해져 원장 쓰기 성능을 희생하므로 채택하지 않음. → [ADR-0005](../02-adr/0005-cdc-debezium-replication.md), [ADR-0020](../02-adr/0020-postgresql-logical-replication.md)

## 6. 백업

| 대상 | 방식 | 보존 |
|---|---|---|
| RDS | 자동 백업 + PITR | 7일 (운영 권장 35일) |
| RDS | 일 1회 스냅샷 | 30일 |
| Cloud SQL | 자동 백업 | 7일 |
| Terraform State | S3/GCS 버전 관리 | 무기한 |
