# ADR-0019: 원장 반영 경로를 Kafka 에서 Redis Stream 으로 변경
- 상태: **Accepted** (승인: 2026-11-26 KST, #30) · 용어 갱신: 본문의 "monolith" 는 core-service 로 읽는다 (#35)
- 날짜: 2026-11-25 KST
- 대체: [ADR-0008](0008-kafka-async-ledger-sync.md) (Kafka 비동기 원장 반영)
- 관련: ADR-0007 (Redis 판정), ADR-0018 (퀴즈 즉시 지급·Failback 지급 원칙), ADR-0004 (선택적 복구), ADR-0020 (DR 복제 — Kafka 제거의 다른 절반)
- 논의: #30 (goal #29)

## 맥락
- 인프라에서 Kafka(MSK)를 빼기로 했다. 원장 반영 경로에서 Kafka 가 맡던 역할을 대신할 수단이 필요하다.
  - **버퍼(피크 격리):** 이벤트 폭주가 monolith·RDS 로 그대로 전파되지 않게 한다 (ADR-0008 의 채택 이유)
  - **재처리:** consumer 가 멈췄다 살아나면 이어서 처리, 실패 건은 DLQ
- 판정은 이미 Redis Lua 로 원자 처리한다 (ADR-0007, `claim_reward.lua`). 지금은 **판정과 발행이 분리**돼 있다.
  - Lua 판정(당첨) → Kafka 발행(최대 3초 동기 대기) → 실패하면 `rollback_reward.lua` 로 당첨을 되돌린다
  - 판정 직후 파드가 죽으면 "Redis 에는 당첨, 메시지는 없음" 인 틈이 남는다 (대사 배치로만 발견 가능)
- ADR-0008 은 "event 가 DB 에 직접 쓰기"를 **서비스 간 DB 공유 = MSA 경계 붕괴**로 기각했다. 이 기각 사유는 그대로 유효하다.

## 결정
**event pod 는 Redis Lua 한 번으로 판정과 기록을 함께 하고, monolith 가 Redis Stream 을 consumer group 으로 읽어 원장에 반영한다.**

```
[참여 요청 폭주]
   │ HTTP
   ▼
event pod ──Lua 1회 (원자)──▶ Redis
   │                          ├ 판정: SADD participants / DECR stock   (낙첨·중복은 여기서 끝)
   │                          └ 당첨이면 같은 스크립트에서 XADD event:{id}:rewards   (당첨 건만)
   ▼
202 당첨 / 200 낙첨 / 409 중복 (DB 를 기다리지 않음)

monolith (consumer group point-ledger) ──XREADGROUP (pull, 자기 속도)──▶ Redis Stream
   └▶ PointService.earn — 원장 INSERT + 지갑 UPDATE, idempotency_key UNIQUE 로 1회만 ──▶ XACK
```

| 항목 | 결정 |
|---|---|
| 원장 쓰기 주체 | **monolith point 모듈만** (ADR-0008 의 경계 유지). event-service 는 DB 계정·원장 로직이 없다 |
| 판정 + 기록 | `claim_reward.lua` 가 당첨 시 `XADD` 까지 수행 → **원자적.** 발행 실패 보상(`rollback_reward.lua`)과 "판정 후 발행 전 장애" 틈이 없어진다 |
| Stream 키 | 퀴즈 `event:{id}:rewards` (기존 키와 같은 해시태그 → 클러스터 모드에서도 같은 슬롯). 출석 `attendance:{yyyyMMdd}:rewards` — 출석 Bitmap 키도 `attendance:{yyyyMMdd}` 해시태그 형식으로 바꿔 같은 스크립트에서 `SETBIT`+`XADD` |
| Stream 발견 | 퀴즈: 이벤트를 열 때 Stream 이름을 등록 Set(`reward:streams`)에 추가 → monolith 가 등록된 Stream 을 읽는다 (참여는 열린 뒤에만 가능하므로 등록이 항상 먼저). 출석: 날짜로 이름이 정해짐 (오늘·어제) |
| 메시지 필드 | 지금의 `point.reward.requested` 와 같은 필드: `idempotencyKey`, `userId`, `eventId`, `amount`, `reason`, `occurredAt` (스키마 `api/events/point.reward.requested.schema.json` 재사용) |
| 소비 | `XREADGROUP GROUP point-ledger <consumer=파드명> BLOCK … STREAMS …` → 반영 성공 시 `XACK`. 반영은 멱등이라 at-least-once 로 충분 |
| 재시도 | 처리 안 된 항목(PEL)은 `XAUTOCLAIM`(min-idle 예: 60초)으로 다른 파드가 가져간다 |
| DLQ | 전달 횟수(`XPENDING` delivery count)가 한도(예: 5)를 넘거나 비재시도 오류(검증 실패)면 `reward:dlq` Stream 에 옮기고 `XACK` — 지금의 `point.reward.dlq` 와 같은 역할 |
| 보존 | `XACK` 된 항목도 **바로 지우지 않는다.** 보존 기간(예: 7일)이 지난 항목만 `XTRIM MINID` 로 정리 (Failback 재반영 근거, 아래 DR) |
| Redis 가용성 | ElastiCache **Multi-AZ + 자동 장애 조치 필수.** 복제는 비동기라 장애 조치 시 마지막 쓰기 일부가 유실될 수 있다 → 필요하면 스크립트 실행 뒤 `WAIT 1 <ms>` 로 복제본 반영을 기다린다 (지연과 맞교환, 구현 시 측정) |
| 설정 | `KAFKA_ENABLED` → `REWARD_STREAM_ENABLED` 류로 교체. DR(gcp-dr) 프로필은 consumer 비활성 (지금과 같음) |

### DR (ADR-0018 Failback 지급 원칙의 Stream 판)
- Stream 은 GCP 로 복제되지 않는다 (지금의 MSK 와 같다). DR 중 미반영 당첨은 **AWS Redis 에 남아 있다가 Failback 후 반영**된다.
- **RDS 에만 커밋된 원장**(ADR-0020 복제 지연분)은 Stream 에서 이미 `XACK` 돼 다시 오지 않는다 → Failback 에서 consumer 재개 전 **consumer group 위치를 되감는다**: Stream ID 가 밀리초 타임스탬프라 `XGROUP SETID <stream> point-ledger <last_replicated_at − 여유(ms)>-0` 으로 Kafka 오프셋 되감기와 같은 효과. 다시 들어오는 항목 중 이미 있는 건은 멱등키로 무시된다.
- 전제: ElastiCache 가 장애를 버텼을 것, 보존 기간 안에 Failback 할 것. Redis 까지 소실되면 미반영 당첨 명단은 복원할 수 없다 (ADR-0018 의 "AWS 영구 소실" 과 같음).

## 고려한 대안
| 대안 | 장점 | 단점 | 기각 이유 |
|---|---|---|---|
| **A. Redis Stream + monolith consumer** | 원장 단일 소유 유지, 피크 격리(pull), 판정+기록 원자화, 기존 멱등 로직 재사용, 추가 인프라 없음 (ElastiCache 는 이미 있음) | 메모리 기반·비동기 복제 → 유실 창, PEL·DLQ·보존을 직접 구현 | **채택** |
| B. event pod 가 RDS 에 직접 쓰기 | 가장 단순, 즉시 지급, DR 미반영분 없음 | 서비스 간 DB 공유, 원장 로직 중복, 피크 시 파드 수 × 커넥션 풀로 RDS 커넥션 고갈 → 로그인·결제까지 영향, 응답 경로에 DB | ADR-0008 과 같은 이유 (경계·격리) |
| C. Redis 에 모아 두고 배치 반영 | 쓰기 횟수 최소 | 지급 지연 | ADR-0018(즉시 지급)과 반대 |
| D. Kafka 유지 | 디스크 복제·보존, 검증된 구조 | 인프라 제거 결정과 충돌 | 전제 조건 |
| E. SQS 등 클라우드 큐 | 관리형·내구성 | GCP 이식성(ADR-0008 기각 사유), 판정과 원자적으로 묶을 수 없음 | 이식성·원자성 |

## 결과
- (+) MSK·MSK Connect 제거 (ADR-0020 과 함께) → 인프라 구성요소·비용 감소
- (+) 판정과 기록이 원자적 → 발행 실패 보상 로직과 "당첨됐는데 메시지 없음" 틈 제거
- (+) 원장 쓰기는 여전히 monolith 한 곳, DB 커넥션 수는 monolith 파드 수로 고정
- (−) 내구성 저하: Kafka(디스크 복제, 7일 보존) → ElastiCache(메모리, 비동기 복제). 장애 조치 시 마지막 쓰기 유실 가능
- (−) Kafka 가 주던 consumer group·DLQ·보존 관리를 애플리케이션이 직접 구현 (PEL 재처리, DLQ Stream, `XTRIM`)
- (−) 클러스터 모드에서는 Stream 이 이벤트별로 나뉘어 monolith 가 Stream 목록을 관리해야 한다
- 후속 (승인 후 구현 sub-issue)
  - point-backend: `claim_reward.lua` 에 `XADD`, 출석 스크립트화(`SETBIT`+`XADD`, 키 해시태그 전환), `RewardPublisher`·`rollback_reward.lua` 제거, monolith `RewardEventConsumer` 를 Stream consumer 로 교체(PEL·DLQ·보존), Kafka 의존성·설정 제거
  - point-infra: MSK 모듈·Strimzi·토픽 문서 제거, ElastiCache Multi-AZ 확인, 데이터·DR 문서(data-architecture §Kafka, dr-runbook Failback 6-1, ADR-0018 DR 표) 갱신, consumer lag 지표(`XPENDING`/Stream 길이) 관측성
