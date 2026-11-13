// S2 Spike: 0 → 5,000 RPS (10초) → 5분 유지
// 실행: k6 run -e BASE_URL=https://api.example.com -e EVENT_ID=evt-test load-test/k6/s2-event-spike.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: 2000,
      maxVUs: 10000,
      stages: [
        { target: 5000, duration: '10s' },
        { target: 5000, duration: '5m' },
        { target: 0, duration: '30s' },
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.001'],
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:8081';
const EVENT = __ENV.EVENT_ID || 'evt-local';

export default function () {
  const userId = Math.floor(Math.random() * 1_000_000);
  // TODO: 사전 발급 JWT 풀에서 토큰 선택
  const res = http.post(`${BASE}/api/events/${EVENT}/answers`,
    JSON.stringify({ answer: 'A' }),
    { headers: { 'Content-Type': 'application/json', 'X-Test-User': `${userId}` } });
  check(res, { 'accepted|ok|dup|closed': (r) => [200, 202, 409, 410].includes(r.status) });
}
