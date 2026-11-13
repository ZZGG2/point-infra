-- RDS (PostgreSQL) 에서 1회 실행: CDC 계정 및 복제 대상 테이블 지정
CREATE ROLE debezium WITH LOGIN PASSWORD :'debezium_password';
GRANT rds_replication TO debezium;
GRANT USAGE ON SCHEMA users, asset, point TO debezium;
GRANT SELECT ON users.app_user, users.user_credential, asset.linked_account,
                point.point_wallet, point.point_ledger, point.refund_request,
                public.dr_heartbeat TO debezium;
GRANT UPDATE ON public.dr_heartbeat TO debezium;   -- heartbeat.action.query

CREATE PUBLICATION dr_publication FOR TABLE
  users.app_user, users.user_credential, asset.linked_account,
  point.point_wallet, point.point_ledger, point.refund_request,
  public.dr_heartbeat;
