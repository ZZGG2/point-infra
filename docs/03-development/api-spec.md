# API 명세 (초안)

Base: `https://api.<domain>` · 인증: `Authorization: Bearer <JWT>` · 응답 공통 포맷 `{ "code": "...", "data": {...}, "message": "..." }`

## monolith

| Method | Path | 설명 | 도메인 |
|---|---|---|---|
| POST | `/api/auth/signup` | 회원가입 | user |
| POST | `/api/auth/login` | 로그인 (JWT 발급) | user |
| GET | `/api/users/me` | 내 정보 | user |
| GET | `/api/assets` | 연동 자산 목록 (Mock 마이데이터) | asset |
| GET | `/api/points/balance` | 포인트 잔액 | point |
| GET | `/api/points/history?cursor=` | 포인트 거래 내역 | point |
| POST | `/api/points/use` | 포인트 사용 (헤더 `Idempotency-Key` 필수) | point |
| POST | `/api/points/refunds` | 환불 요청 | point |
| GET | `/api/cs/notices` | 공지 목록 | cs |

## event-service

| Method | Path | 설명 | 응답 |
|---|---|---|---|
| GET | `/api/events/active` | 진행 중 이벤트 | 200 |
| POST | `/api/events/attendance` | 출석체크 | 202 지급 예정 / 409 이미 출석 |
| POST | `/api/events/{eventId}/queue` | 대기열 진입 | 200 `{ position }` |
| GET | `/api/events/{eventId}/queue/me` | 내 순번 | 200 `{ position, admitted }` |
| POST | `/api/events/{eventId}/answers` | 퀴즈 정답 제출 | 202 당첨(지급 예정) / 200 낙첨 / 409 중복 / 410 마감 |

## 운영·인프라 검증 (ops)

읽기 전용. 구성요소가 죽어 있어도 200 으로 응답하고 각 `status`(UP/DOWN/DISABLED) 로 구분한다. 끄려면 `OPS_API_ENABLED=false`.

| 서비스 | Method | Path | 설명 |
|---|---|---|---|
| monolith | GET | `/api/system/info` | 응답 Pod·프로필·DR 모드, PostgreSQL(버전·접속 노드·`pg_is_in_recovery`·`dr_heartbeat` 경과), Kafka(`point-ledger` 컨슈머 lag) |
| monolith | GET | `/api/system/whoami` | 응답 Pod 정보만 (부하 분산 확인용) |
| monolith | GET | `/api/system/ledger?recent=` | 원장 집계(지갑 수·잔액 합·출처별 합계) + 전체 사용자 최근 활동 |
| event-service | GET | `/api/events/system/info` | 응답 Pod, Redis(버전·role·PING), Kafka(토픽·누적 발행 offset). DR 모드에서는 503 `EVENT_MAINTENANCE` |
| event-service | GET | `/api/events/system/whoami` | 응답 Pod 정보만 |

## DR 모드

| 경로 | 동작 |
|---|---|
| `/api/events/**` | 503 `{ "code": "EVENT_MAINTENANCE", "message": "이벤트는 시스템 점검으로 일시 중단되었습니다." }` |
| 그 외 | 정상 |

## Kafka 메시지: `point.reward.requested`

```json
{
  "idempotencyKey": "evt-20261111-quiz:1004",
  "userId": 1004,
  "eventId": "evt-20261111-quiz",
  "amount": 500,
  "reason": "QUIZ_REWARD",
  "occurredAt": "2026-11-11T10:00:01.234+09:00"
}
```
