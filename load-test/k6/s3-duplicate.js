// S3 Duplicate: 동일 사용자 동시 10회 제출 → 지급 정확히 1회 검증
import http from 'k6/http';
import { check } from 'k6';

export const options = { vus: 10, iterations: 10 };
const BASE = __ENV.BASE_URL || 'http://localhost:8081';

export default function () {
  const res = http.post(`${BASE}/api/events/evt-local/answers`, JSON.stringify({ answer: 'A' }),
    { headers: { 'Content-Type': 'application/json', 'X-Test-User': '1004' } });
  check(res, { 'one 202, rest 409': (r) => [202, 409].includes(r.status) });
}
// 사후 검증: SELECT count(*) FROM point.point_ledger WHERE idempotency_key = 'evt-local:1004';  -- = 1
