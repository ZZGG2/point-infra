# ADR-0020: DR 복제를 PostgreSQL 네이티브 논리 복제로 변경
- 상태: **Accepted** (승인: 2026-11-26 KST, #31)
- 날짜: 2026-11-25 KST
- 대체: [ADR-0005](0005-cdc-debezium-replication.md) (Debezium CDC 기반 비동기 복제)
- 관련: ADR-0010 (DR 독립성), ADR-0013 (RDS), ADR-0018 (Failback 지급 원칙), ADR-0019 (Kafka 제거의 다른 절반)
- 논의: #31 (goal #29) · 리뷰 요청: CDC·DR runbook 담당(#8)

## 맥락
- 인프라에서 Kafka(MSK)를 빼면 `RDS → Debezium Source → MSK → JDBC Sink → Cloud SQL` 경로가 사라진다 (MSK Connect 는 MSK 전용).
- 복제 요구는 그대로다: 핵심 테이블만, 비동기, **RPO near-zero (목표 p99 ≤ 5초)**, DR 경로는 AWS 에 의존하지 않음 (ADR-0010).
- ADR-0005 는 네이티브 논리 복제를 **"구독 측이 원천에 직접 접속, 모니터링/재처리 수단 약함 — 관측성"** 으로 기각했다. 이 ADR 은 그 사유에 답해야 한다.
- 지금 구조에는 논리 복제가 더 나은 점도 있다: JDBC Sink 는 테이블별 토픽을 병렬로 소비해 원장과 지갑이 서로 다른 시점에서 끊길 수 있었다 (그래서 `reconcile-wallet.sql` 이 필요했다).

## 결정
**RDS 를 발행자(PUBLICATION), Cloud SQL 을 구독자(SUBSCRIPTION)로 하는 PostgreSQL 네이티브 논리 복제(pgoutput)를 사용한다.**

```
RDS (PUBLICATION dr_publication, slot) ◀──── 접속·수신 (HA VPN) ──── Cloud SQL (SUBSCRIPTION dr_subscription)
```

| 항목 | 결정 |
|---|---|
| 복제 대상 | 지금 `cdc/publication.sql` 의 `dr_publication` 테이블 그대로 (users.app_user, user_credential, asset.linked_account, point.point_wallet, point_ledger, refund_request, public.dr_heartbeat). 기본 키 필수 |
| 복제 계정 | RDS 에 `dr_replicator` (`rds_replication` + 대상 테이블 SELECT). 비밀번호는 Secrets Manager / GCP Secret Manager (평문 금지) |
| 구독 생성 | Cloud SQL 에서 `CREATE SUBSCRIPTION dr_subscription CONNECTION '…' PUBLICATION dr_publication WITH (copy_data = true)` — 첫 동기화는 초기 복사 |
| 네트워크 | **방향이 반대가 된다.** 지금: AWS(MSK Connect) → GCP 5432. 바꾼 뒤: **GCP(Cloud SQL 사설 IP 대역 10.30.0.0/20) → RDS 5432.** sg-rds 인바운드에 `10.30.0.0/20:5432` 추가, sg-msk-connect 삭제, VPN 경로·PSA 피어링 export 로 RDS 대역이 Cloud SQL 까지 보여야 한다 |
| 적용 순서 | 커밋 순서대로 트랜잭션 단위 적용 → 원장·지갑이 같은 트랜잭션 경계에서 끊긴다 |
| DDL | 복제되지 않음 (지금과 같음) → Flyway 를 양쪽에 먼저 적용, 테이블 추가 시 `ALTER PUBLICATION … ADD TABLE` + `ALTER SUBSCRIPTION … REFRESH PUBLICATION` |
| 시퀀스 | 복제되지 않음 (지금과 같음) → `fix-sequences.sql` 유지 (여유분 100000 — Failback 역방향 시 ID 충돌 방지 역할도 함) |

### ADR-0005 기각 사유("관측성")에 대한 답
| 걱정 | 대책 |
|---|---|
| 복제 지연을 볼 수 없다 | RDS: `pg_stat_replication`(write/flush/replay lag), `pg_replication_slots`(confirmed_flush_lsn), CloudWatch `OldestReplicationSlotLag`·`TransactionLogsDiskUsage`. Cloud SQL: `pg_stat_subscription`(last_msg_receipt_time) |
| RPO 근거(heartbeat)가 사라진다 | Debezium `heartbeat.action.query` 대신 **RDS `pg_cron`** 이 `public.dr_heartbeat.ts` 를 주기적으로 갱신 → Cloud SQL 의 `now() - ts` 로 지연, 장애 후 `ts` 로 `last_replicated_at` (지금 `cdc/README` 의 측정 방법 그대로). pg_cron 의 초 단위 스케줄 지원 버전은 **공식 문서 확인 필요** |
| 재처리 수단이 없다 | 오프셋 재처리 대신 **slot 이 끊긴 지점부터 이어서 전송**한다. slot 을 잃으면 구독 재생성 + 초기 복사(copy_data)로 다시 맞춘다 |
| 구독자가 끊기면 원천이 위험하다 | slot 이 WAL 을 붙잡아 **RDS 디스크가 찰 수 있다** → `max_slot_wal_keep_size` 로 상한, `OldestReplicationSlotLag`·디스크 알람. 상한을 넘으면 slot 이 무효화되고 재동기화가 필요하다 (원천 보호 우선) |

### DR 절차 변경 (dr-runbook)
- **Failover 승격(7단계):** AWS 가 응답하지 않는 상태에서 그냥 `DROP SUBSCRIPTION` 하면 원격 slot 을 지우려다 멈춘다 → `ALTER SUBSCRIPTION dr_subscription DISABLE` → `ALTER SUBSCRIPTION dr_subscription SET (slot_name = NONE)` → `DROP SUBSCRIPTION`. 지금의 `sink_writer NOLOGIN` 단계는 구독 해제로 대체, `app_rw LOGIN`·`fix-sequences.sql` 은 유지. `reconcile-wallet.sql` 은 트랜잭션 단위 적용으로 필요성이 줄지만 안전장치로 유지 (드릴에서 drift 0 이 확인되면 재검토)
- **RDS 쪽 정리:** AWS 복구 후 남은 slot(`dr_subscription`)을 지운다 — 그대로 두면 WAL 이 계속 쌓인다
- **Failback 동기화(2단계):** 같은 기능으로 역방향 — Cloud SQL 에 PUBLICATION, RDS 에 SUBSCRIPTION. 단 **RDS 에만 커밋된 행(복제 지연분)이 있으면 고유키 충돌로 apply 가 멈춘다** → 역방향 구독 전에 RDS 의 미복제 행을 따로 빼 두고(ledger 는 `idempotency_key` 기준) 동기화 후 다시 반영하거나, ADR-0019 의 Stream 되감기로 다시 지급한다. 지급 원칙은 ADR-0018 그대로 (DB 에 반영된 건 유지, 미반영분만 반영)
- **드릴:** 클론 인스턴스 승격 방식 유지. 드릴 중에도 원본 구독은 유지된다

## 고려한 대안
| 대안 | 장점 | 단점 | 기각 이유 |
|---|---|---|---|
| **A. PostgreSQL 네이티브 논리 복제** | 추가 구성요소 없음(MSK·Connect 제거), 트랜잭션 단위 적용, Failback 역방향도 같은 기능, 양쪽 관리형에서 표준 기능 | 구독자 → 원천 접속(네트워크 방향 변경), slot WAL 위험, 시퀀스·DDL 미복제, heartbeat 직접 구성 | **채택** (관측성은 위 대책으로 보완) |
| B. pglogical 확장 | Cloud SQL 공식 지원, 시퀀스 동기화 기능 | 양쪽 확장 설치·버전 맞춤, 네이티브보다 운영 사례 적음 | A 에서 **Cloud SQL 이 네이티브 구독을 지원하지 않으면 대안** |
| C. GCP Database Migration Service | 관리형 지속 복제(내부적으로 pglogical) | 마이그레이션 목적 도구, 테이블 선택·장기 운영 유연성 제한 | ADR-0005 와 같음 (Plan B 유지) |
| D. Debezium + Kafka (Strimzi 등 자체 운영) | 검증된 설계, 오프셋 재처리 | Kafka 제거 결정과 충돌, 자체 운영 부담 | 전제 조건 |
| E. 동기 복제 / 주기 덤프 | RPO 0 / 단순 | 가용성·성능 희생 / RPO 수 시간 | ADR-0005 와 같음 |

## 결과
- (+) MSK·MSK Connect·Debezium 플러그인 제거 (ADR-0019 와 함께) → 비용·운영 요소 감소
- (+) 트랜잭션 단위 적용으로 원장·지갑 불일치 감소
- (+) Failback 역방향 복제를 같은 기능으로 구성
- (−) 네트워크 방향이 바뀐다 (GCP → AWS 5432 허용). DR 경로 독립성(ADR-0010)은 유지 — Failover 때 구독을 끊을 뿐 AWS 를 참조하지 않는다
- (−) slot WAL 누적 위험 → 알람·상한 필수. 구독이 오래 끊기면 재동기화(초기 복사) 필요
- (−) RPO 측정용 heartbeat 를 pg_cron 으로 직접 구성
- 확인 필요 (승인 전): Cloud SQL for PostgreSQL 16 에서 네이티브 `CREATE SUBSCRIPTION` 에 필요한 권한(`cloudsqlsuperuser` / `pg_create_subscription`)과 제약 — **공식 문서 확인 필요.** 지원하지 않으면 대안 B
- 후속 (승인 후 구현 sub-issue): `cdc/` 를 publication·subscription SQL 로 재작성(Debezium JSON 삭제), Terraform(sg-rds 규칙, sg-msk-connect·MSK 모듈 제거, RDS 파라미터 `max_slot_wal_keep_size`·pg_cron), dr-runbook·dr-strategy·network-design·data-architecture §4 갱신, `promote-cloudsql.sh`·`record-rpo.sh` 수정, slot lag 알람
