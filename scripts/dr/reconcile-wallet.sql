-- Failover 시 지갑 잔액을 원장 기준으로 맞춘다 (fix-sequences.sql 직후, 앱 트래픽 유입 전 1회)
--
-- 이유: Debezium JDBC Sink 는 테이블별 토픽(cdc.point.point_ledger / cdc.point.point_wallet)을
--       병렬 태스크로 소비한다 → 트랜잭션 단위 원자성이 없어, 복제가 끊긴 순간
--       원장만 반영되고 지갑은 이전 값(또는 반대)인 상태가 남을 수 있다.
-- 기준: 원장(append-only)이 Source of Truth. 지갑 = 사용자별 마지막 원장 행의 balance_after.
--       원장은 수정하지 않는다. 지갑은 원장에서 파생된 값이므로 보정 대상이다.
BEGIN;

CREATE TEMP TABLE wallet_drift ON COMMIT DROP AS
SELECT w.user_id, w.balance AS wallet_balance, COALESCE(l.balance_after, 0) AS ledger_balance
FROM point.point_wallet w
LEFT JOIN LATERAL (
  SELECT balance_after FROM point.point_ledger pl
  WHERE pl.user_id = w.user_id
  ORDER BY pl.id DESC
  LIMIT 1
) l ON true
WHERE w.balance <> COALESCE(l.balance_after, 0);

-- 불일치 내역은 Failback 대사 근거로 로그에 남긴다
SELECT count(*) AS drift_count FROM wallet_drift;
SELECT * FROM wallet_drift ORDER BY user_id;

UPDATE point.point_wallet w
SET balance = d.ledger_balance, version = w.version + 1, updated_at = now()
FROM wallet_drift d
WHERE w.user_id = d.user_id;

-- 원장은 복제됐는데 지갑 행이 아직 없는 사용자
INSERT INTO point.point_wallet (user_id, balance)
SELECT DISTINCT ON (pl.user_id) pl.user_id, pl.balance_after
FROM point.point_ledger pl
WHERE NOT EXISTS (SELECT 1 FROM point.point_wallet w WHERE w.user_id = pl.user_id)
ORDER BY pl.user_id, pl.id DESC;

COMMIT;
