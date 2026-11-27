-- Cloud SQL (PostgreSQL 16) point DB 에서 1회 실행: RDS 의 dr_publication 구독 (ADR-0020)
-- usage: psql ... -v rds_conninfo="host=<RDS 엔드포인트> port=5432 dbname=point user=dr_replicator password=<Secret Manager> sslmode=require" -f cdc/subscription.sql
--   접속 정보·비밀번호는 Secret Manager 에서 주입한다 (파일·커밋에 쓰지 않는다)
-- 전제
--   - 스키마는 Flyway 로 먼저 적용 (DDL 은 복제되지 않는다)
--   - Cloud SQL → RDS 5432 경로: HA VPN + sg-rds 인바운드 10.30.0.0/20 (network-design.md)
--   - 실행 계정에 필요한 권한(cloudsqlsuperuser / pg_create_subscription)과 제약: 공식 문서 확인 필요 (ADR-0020)
-- 앱 계정(app_rw)은 평시 NOLOGIN. 평시 쓰기는 구독 apply 만 있다. 승격 시 scripts/dr/promote-cloudsql.sh

CREATE SUBSCRIPTION dr_subscription
  CONNECTION :'rds_conninfo'
  PUBLICATION dr_publication
  WITH (copy_data = true);   -- 첫 동기화는 초기 복사. RDS 에 slot 'dr_subscription' 이 생긴다

-- 상태 확인
--   SELECT subname, received_lsn, latest_end_lsn, last_msg_receipt_time FROM pg_stat_subscription;
--   SELECT srrelid::regclass, srsubstate FROM pg_subscription_rel;   -- 초기 복사 진행 (r = 완료)
