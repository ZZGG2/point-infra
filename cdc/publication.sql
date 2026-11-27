-- RDS (PostgreSQL) 에서 1회 실행: 복제 계정, 복제 대상 테이블(PUBLICATION), heartbeat (ADR-0020)
-- usage: psql -d point ... -v dr_replicator_password="$(Secrets Manager 에서 조회)" -f cdc/publication.sql   (1·2 는 point DB, 3 은 postgres DB)
-- 전제: 파라미터 그룹 rds.logical_replication=1, shared_preload_libraries 에 pg_cron, max_slot_wal_keep_size 설정

-- 1. 복제 계정 — Cloud SQL 구독이 이 계정으로 RDS 에 접속한다
CREATE ROLE dr_replicator WITH LOGIN PASSWORD :'dr_replicator_password';
GRANT rds_replication TO dr_replicator;
GRANT USAGE ON SCHEMA users, asset, point TO dr_replicator;
GRANT SELECT ON users.app_user, users.user_credential, asset.linked_account,      -- 초기 복사(copy_data)용
                point.point_wallet, point.point_ledger, point.refund_request,
                public.dr_heartbeat TO dr_replicator;

-- 2. 복제 대상 테이블 (기본 키 필수)
CREATE PUBLICATION dr_publication FOR TABLE
  users.app_user, users.user_credential, asset.linked_account,
  point.point_wallet, point.point_ledger, point.refund_request,
  public.dr_heartbeat;

-- ADR-0018: 일괄 정산 테이블(reward_pending, event_settlement)은 미사용 → Publication 에서 뺐다.
--   이미 추가한 환경: ALTER PUBLICATION dr_publication DROP TABLE point.reward_pending, point.event_settlement;
-- 테이블 추가 시: ALTER PUBLICATION dr_publication ADD TABLE ... → Cloud SQL 에서 ALTER SUBSCRIPTION dr_subscription REFRESH PUBLICATION;

-- 3. heartbeat — 1초마다 dr_heartbeat.ts 갱신 → Cloud SQL 에서 복제 지연·마지막 복제 시각 측정 (cdc/README.md)
--    pg_cron 은 postgres DB 에 설치하고 point DB 에서 실행되도록 등록한다.
--    초 단위 스케줄('1 seconds')과 schedule_in_database 지원 버전: 공식 문서 확인 필요 (ADR-0020)
\connect postgres
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule_in_database(
  'dr-heartbeat', '1 seconds',
  $$UPDATE public.dr_heartbeat SET ts = now() WHERE id = 1$$,
  'point');
