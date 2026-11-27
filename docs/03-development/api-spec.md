# API 명세

> 계약의 원본은 **`point-backend/api/openapi.yaml`** (프론트는 여기서 타입 생성). 이 문서는 설계 관점의 목록이며 `상태` 열로 구현 여부를 표시한다.
> 상태: ✅ 구현 · ❌ 설계만 (미구현) · 🧪 `local` 프로필 전용 — 전체 현황: [implementation-status](../00-overview/implementation-status.md)

Base: `https://api.<domain>` · 인증: `Authorization: Bearer <access token>` · 응답 공통 포맷 `{ "code": "...", "data": {...}, "message": "..." }`

## 인증 방식
| 토큰 | 형태 | 수명 (기본) | 전달 · 저장 |
|---|---|---|---|
| access token | RS256 JWT (`iss=point-core`, `sub`=사용자 id) | 15분 (`JWT_ACCESS_TTL`) | 응답 본문 → 브라우저 메모리, 요청 헤더 `Authorization: Bearer` |
| refresh token | 256bit 랜덤 | 14일 (`JWT_REFRESH_TTL`) | HttpOnly 쿠키 `point_refresh` (`Path=/api/auth`, `SameSite=Strict`, Secure=`AUTH_COOKIE_SECURE`). DB 에는 SHA-256 해시만 |

- refresh 는 **한 번 쓰면 폐기하고 새로 발급**(rotation) → 탈취된 토큰은 한 번만 유효. 로그아웃 시 폐기.
- event-service 는 core-service 를 호출하지 않고 공개키(`JWT_PUBLIC_KEY`, 없으면 `JWT_JWK_SET_URI`)로 자체 검증 (hybrid-msa §4).
- `refresh_token` 테이블은 CDC 복제 대상이 아니다 → DR 전환 후에는 다시 로그인 (access token 은 양쪽 같은 서명 키면 유효).

## core-service

| Method | Path | 설명 | 도메인 | 상태 |
|---|---|---|---|---|
| POST | `/api/auth/signup` | 회원가입 → 바로 로그인 (access 본문 + refresh 쿠키) | user | ✅ |
| POST | `/api/auth/login` | 로그인 (JWT 발급 + refresh 쿠키) | user | ✅ |
| POST | `/api/auth/refresh` | refresh 쿠키로 access 재발급 + refresh 교체 | user | ✅ |
| POST | `/api/auth/logout` | refresh 폐기 + 쿠키 삭제 | user | ✅ |
| GET | `/api/auth/jwks.json` | 서명 공개키 (JWKS) | user | ✅ |
| GET | `/api/users/me` | 내 정보 | user | ✅ |
| GET | `/api/assets` | 연동 자산 목록 (Mock 마이데이터) | asset | ❌ |
| GET | `/api/points/balance` | 포인트 잔액 | point | ✅ |
| GET | `/api/points/history` | 포인트 거래 내역 — **현재 최근 20건 고정** | point | ✅ |
| GET | `/api/points/history?cursor=` | 커서 페이지네이션 (`(created_at, id)` keyset) · 기간/유형 필터 | point | ❌ |
| POST | `/api/points/use` | 포인트 사용 (헤더 `Idempotency-Key` 필수, 사용자별로 범위 구분 `use:{userId}:{key}`) · 잔액 부족 409 | point | ✅ |
| POST | `/api/points/refunds` | 환불 요청 | point | ❌ |
| GET | `/api/cs/notices` | 공지 목록 | cs | ❌ |
| GET | `/api/health` | 앱 헬스 (화면 점검 감지용) | common | ✅ |

## event-service

| Method | Path | 설명 | 응답 | 상태 |
|---|---|---|---|---|
| GET | `/api/events/active` | 진행 중 이벤트 | 200 | ❌ |
| POST | `/api/events/attendance` | 출석체크 (KST 하루 1회) | 202 지급 예정 / 409 이미 출석 | ✅ |
| POST | `/api/events/{eventId}/queue` | 대기열 진입 | 200 `{ position }` | ❌ |
| GET | `/api/events/{eventId}/queue/me` | 내 순번 | 200 `{ position, admitted }` | ❌ |
| POST | `/api/events/{eventId}/answers` | 퀴즈 정답 제출 | 202 당첨(지급 예정 — Redis Stream 경유 원장 반영, 보통 1초 안쪽) / 200 낙첨(재고 소진) / 409 중복 / 410 이벤트 없음·마감 | ✅ |
| POST | `/api/events/admin/{eventId}` | 운영용 이벤트 생성 `{stock, amount, endsAt}` (`X-Admin-Token`) | 201 상태 / 403 토큰 / 409 이미 쓴 id | ✅ |
| GET | `/api/events/{eventId}/status` | 재고·참여자·당첨자 수·마감 시각 `endsAt` (인증 없음) | 200 | ✅ |
| POST | `/api/events/{eventId}/open?stock=&amount=` | 이벤트 열기·초기화 (인증 없음, 마감 없음) | 200 상태 | 🧪 |

- 생성 API 는 [event-day 런북](../05-operations/runbooks/event-day.md) D-1 에서 curl 로 호출한다. 프론트에서는 부르지 않는다 (브라우저에 관리자 토큰을 두지 않음). 경로가 `/api/events` 아래인 이유: Gateway 가 `/api/events/**` 만 event-service 로 보낸다
  - 토큰: event-service `ADMIN_API_TOKEN` (비어 있으면 항상 403)
  - 한 번 쓴 `eventId` 는 다시 쓸 수 없다 (409) — 같은 id 를 다시 열면 멱등키(`eventId:userId`)가 겹쳐 새 당첨이 원장에서 무시된다
  - `endsAt` 이 지나면 참여 마감(answers → 410). 이벤트 키는 `endsAt` + 1일에 만료 (ADR-0007), 보상 Stream 은 만료되지 않는다 (ADR-0019, 7일 보존)
- 🧪 `open` 은 `@Profile("local")` 이라 aws·gcp-dr 프로필에는 없다 (데모·테스트용 초기화)
- 프론트 이벤트 화면은 `status` 만 호출한다 (관리자 패널은 조회 전용, point-frontend#4)

## 운영·인프라 검증 (ops)

읽기 전용. 구성요소가 죽어 있어도 200 으로 응답하고 각 `status`(UP/DOWN/DISABLED) 로 구분한다. 끄려면 `OPS_API_ENABLED=false`.

| 서비스 | Method | Path | 설명 |
|---|---|---|---|
| core-service | GET | `/api/system/info` | 응답 Pod·프로필·DR 모드, PostgreSQL(버전·접속 노드·`pg_is_in_recovery`·`dr_heartbeat` 경과), Redis Stream(consumer group `point-ledger` 의 pending 수·DLQ 길이) |
| core-service | GET | `/api/system/whoami` | 응답 Pod 정보만 (부하 분산 확인용) |
| core-service | GET | `/api/system/ledger?recent=` | 원장 집계(지갑 수·잔액 합·출처별 합계) + 전체 사용자 최근 활동 |
| event-service | GET | `/api/events/system/info` | 응답 Pod, Redis(버전·role·PING·등록된 보상 Stream 수 `rewardStreams`). DR 모드에서는 503 `EVENT_MAINTENANCE` |
| event-service | GET | `/api/events/system/whoami` | 응답 Pod 정보만 |

## 관리자 (admin)

없음. ADR-0017 의 일괄 정산 API(`/api/admin/events/{id}/settlement`, `X-Admin-Token`)는 ADR-0018 로 제거됐다.

## DR 모드

| 경로 | 동작 |
|---|---|
| `/api/events/**` | 503 `{ "code": "EVENT_MAINTENANCE", "message": "이벤트는 시스템 점검으로 일시 중단되었습니다." }` |
| 그 외 | 정상 |

## 원장 반영 메시지: Redis Stream (ADR-0019)

Stream 항목의 필드. 스키마는 `point.reward.requested` 그대로 쓴다 (`api/events/point.reward.requested.schema.json`).

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

| 필드 | 값 |
|---|---|
| `reason` | `QUIZ_REWARD`, `ATTENDANCE_REWARD` → 둘 다 원장에 즉시 멱등 반영 (ADR-0018). 로그·대사 구분용 |
| `idempotencyKey` | `{eventId}:{userId}` — 출석은 `eventId = attendance-{yyyyMMdd}` |
| Stream | 퀴즈 `event:{id}:rewards`, 출석 `attendance:{yyyyMMdd}:rewards`. event-service Lua 가 판정과 같은 스크립트에서 `XADD` |
| Consumer group | `point-ledger` (core-service). 반영 성공 시 `XACK` |
- 소비 실패: PEL 에 남은 항목을 min-idle 후 `XPENDING` + `XCLAIM` 으로 재시도, 전달 횟수 한도(예: 5) 초과 또는 비재시도 오류면 `reward:dlq` Stream 으로 이동
