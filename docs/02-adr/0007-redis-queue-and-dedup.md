# ADR-0007: Redis 기반 대기열·중복 방지
- 상태: Accepted · 날짜: 2026-11-05

## 결정
이벤트 참여 판정(중복 방지, 선착순 재고, 대기열 순번)은 **ElastiCache Redis**에서 **Lua 스크립트로 원자 처리**한다. DB는 판정 경로에 두지 않는다.

## 이유
- 피크 시 RDB 행 잠금(`SELECT ... FOR UPDATE`)은 단일 행 경합으로 처리량이 급락한다.
- Redis 단일 스레드 + Lua = 별도 락 없이 원자성 확보, 초당 수만 건 처리.

## 키 설계
| 키 | 타입 | 용도 | TTL |
|---|---|---|---|
| `event:{id}:stock` | String(int) | 남은 당첨 수량 | 이벤트 종료 + 1일 |
| `event:{id}:participants` | Set | 중복 참여 방지 | 동일 |
| `event:{id}:queue` | Sorted Set (score=진입시각) | 대기열 순번 | 동일 |
| `attendance:{yyyyMMdd}` | Bitmap (offset=userId) | 출석체크 | 2일 |

## 결과
- (−) Redis는 Source of Truth가 아니다 → 원장은 Kafka 경유 DB 반영, 종료 후 대사 배치
- (−) DR 대상 아님 (ADR-0004)
