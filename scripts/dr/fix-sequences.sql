-- Failover 후 IDENTITY/시퀀스 보정 (시퀀스 값은 CDC 로 복제되지 않음)
-- 여유분(100000)을 두어 미복제 구간과 ID 충돌 방지
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
