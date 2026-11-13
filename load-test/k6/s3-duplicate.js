// S3 Duplicate: 동일 사용자 동시 10회 제출 → 판정(당첨/낙첨) 정확히 1회, 나머지 9회는 409 중복
// 실행: k6 run -e BASE_URL=http://localhost:8081 -e EVENT_ID=evt-local -e USER_ID=1004 load-test/k6/s3-duplicate.js
// 전제: 이벤트가 열려 있고 USER_ID 가 아직 참여하지 않은 상태 (로컬: POST /api/events/{id}/open 으로 초기화)
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const accepted = new Counter('first_claims');   // 202 당첨 또는 200 낙첨 = 최초 판정
const duplicates = new Counter('duplicates');   // 409
const unexpected = new Counter('unexpected');   // 그 외 (410 마감, 4xx/5xx)

http.setResponseCallback(http.expectedStatuses({ min: 200, max: 299 }, 409));

export const options = {
  vus: 10,
  iterations: 10,
  thresholds: {
    // 10건이 모두 202 여도 통과하던 문제 → 횟수로 검증
    first_claims: ['count==1'],
    duplicates: ['count==9'],
    unexpected: ['count==0'],
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:8081';
const EVENT = __ENV.EVENT_ID || 'evt-local';
const USER = __ENV.USER_ID || '1004';

export default function () {
  const res = http.post(`${BASE}/api/events/${EVENT}/answers`, JSON.stringify({ answer: 'A' }),
    { headers: { 'Content-Type': 'application/json', 'X-User-Id': USER } });
  if (res.status === 200 || res.status === 202) accepted.add(1);
  else if (res.status === 409) duplicates.add(1);
  else unexpected.add(1);
  check(res, { 'claim(200/202) or duplicate(409)': (r) => [200, 202, 409].includes(r.status) });
}
// 사후 검증 (당첨이었을 때): SELECT count(*) FROM point.point_ledger WHERE idempotency_key = '<EVENT_ID>:<USER_ID>';  -- = 1
