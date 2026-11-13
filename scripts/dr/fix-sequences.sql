-- Failover 후 IDENTITY/시퀀스 보정 (시퀀스 값은 CDC 로 복제되지 않음)
-- 여유분(100000)을 두어 미복제 구간과 ID 충돌 방지
-- cs 는 CDC 복제 대상이 아니지만(DR 에서 빈 상태로 새로 쓰기 시작) 의도적으로 포함한다:
--   1부터 다시 채번하면 Failback 시 AWS 쪽 cs ID 와 겹치므로 같은 여유분을 둔다
-- 지갑 잔액 보정은 이어서 reconcile-wallet.sql 실행
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT n.nspname AS schema_name, c.relname AS table_name, a.attname AS column_name,
           pg_get_serial_sequence(format('%I.%I', n.nspname, c.relname), a.attname) AS seq
    FROM pg_attribute a
    JOIN pg_class c ON a.attrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE a.attidentity IN ('a','d') AND n.nspname IN ('users','asset','point','cs')
  LOOP
    EXECUTE format('SELECT setval(%L, COALESCE((SELECT max(%I) FROM %I.%I), 0) + 100000)',
                   r.seq, r.column_name, r.schema_name, r.table_name);
  END LOOP;
END $$;
