# ADR-0018: 퀴즈 당첨 보상을 다시 즉시 지급 (ADR-0017 철회)
- 상태: **Proposed** (팀 승인 전 — 승인되면 ADR-0017 을 `Superseded by ADR-0018` 로 변경) · 날짜: 2026-11-24 KST
- 대체: [ADR-0017](0017-quiz-batch-settlement.md) (퀴즈 이벤트 보상을 이벤트 종료 후 일괄 정산)
- 관련: ADR-0004 (선택적 복구), ADR-0005 (CDC 비동기 복제), ADR-0007 (Redis 판정), ADR-0008 (Kafka 비동기 원장 반영)

## 맥락
- ADR-0017 은 재해 시 "같은 이벤트 당첨자 중 일부만 지급된 상태"를 없애려고 퀴즈 보상을 **이벤트 종료 후 관리자 정산 API 로 일괄 지급**하게 했다.
- 실제로 써 보니 서비스 흐름이 나빴다.
  - 당첨 직후 잔액·내역에 아무 변화가 없다 → 사용자는 "당첨됐는데 왜 포인트가 없지?" 를 겪는다 (CS 유발).
  - 이벤트마다 운영자가 정산 Job(당첨자 수 확인 → `expectedCount` → 409 재시도)을 돌려야 하고, 자동화(이벤트 종료 훅·CronJob)·이벤트 메타데이터 저장소가 아직 없다.
  - 관리자 API 를 임시 `X-Admin-Token` 으로 보호해야 했고, local 프로필에서 토큰이 덮어써지는 문제도 생겼다.
- 출석 보상은 처음부터 즉시 지급이라, 같은 Kafka 토픽·consumer 에서 두 가지 지급 방식이 공존하는 복잡도도 있었다.

## 결정
퀴즈 당첨(`reason=QUIZ_REWARD`)도 출석과 같이 **core-service consumer 가 원장에 바로 멱등 반영**한다 (ADR-0008 원래 흐름).

```
Redis Lua 판정(202) → Kafka point.reward.requested → core-service consumer
  → point_ledger INSERT (idempotency_key = {eventId}:{userId}, UNIQUE) + point_wallet UPDATE → 잔액 즉시 반영 (보통 1초 안쪽)
```

- 관리자 정산 API(`GET/POST /api/admin/events/{id}/settlement`), 정산 서비스·리포지토리·테스트를 제거한다.
- `X-Admin-Token` 검사(`common/security/AdminApiGuard`)와 `/api/admin/**` 공개 경로 설정은 **공통 모듈이라 이번에 건드리지 않는다** (AGENTS.md §3). 호출하는 곳이 없어 미사용 상태로 남고, 정리는 사람이 별도 이슈로 한다.
- Flyway `V202611170200__reward_settlement.sql` 은 **이미 적용된 환경이 있으므로 파일을 남긴다** (지우면 Flyway validate 실패). `point.reward_pending`, `point.event_settlement` 테이블은 빈 채로 남고 앱은 쓰지 않는다. 정리가 필요하면 미정산 행이 없는지 확인한 뒤 별도 마이그레이션으로 DROP 한다.
- DR 승격의 `settle-incomplete-events.sql` 단계, CDC Publication 의 두 테이블, 이벤트 종료 후 정산 런북 단계를 제거한다.

## DR 에 미치는 영향 (ADR-0017 이 막던 문제가 돌아온다)
**원칙:** DR 중에는 event-service 를 복구하지 않는다(ADR-0004). DB 에 이미 반영된 지급은 그대로 두고, **반영되지 않은 지급만 AWS 복구 후 MSK 에 남은 메시지로 반영**한다 (멱등키로 중복 없음).

| 상황 | 결과 | 대응 |
|---|---|---|
| 피크 중 재해, 일부 당첨이 MSK 에만 있음 (consumer lag) | DR(Cloud SQL) 쪽에는 **일부 당첨자만 지급된 상태** | DR 중에는 그대로 운영. 지급된 건은 원장이 정본 |
| Failback (AWS 복구) | MSK 잔여 메시지를 consumer 가 이어서 소비 → 나머지 당첨자 지급. 이미 지급된 건은 `idempotency_key` UNIQUE 로 무시 | 자동 (멱등) — 단 아래 두 경계 조건을 runbook 으로 막는다 |
| RDS 에는 커밋됐지만 CDC 지연(≤ 5초)으로 Cloud SQL 에 없는 원장 | 이 메시지들은 MSK 오프셋이 **이미 커밋됨** → Failback 동기화에서 RDS 를 Cloud SQL 기준으로 덮어쓰면 DB 에서도 사라지고 MSK 에서도 다시 오지 않는다 | consumer 재개 전 **오프셋을 `last_replicated_at` − 여유 시각으로 되감는다**. 다시 들어오는 메시지 중 이미 있는 건은 멱등키로 무시, 빠진 건만 채워진다 ([dr-runbook §5](../06-disaster-recovery/dr-runbook.md#5-failback-절차-계획된-점검) 6-1) |
| DR 기간이 토픽 보존 기간(7일)을 넘김 | 미반영 메시지가 만료돼 **복원 불가** | 보존 기간을 예상 최대 DR 기간 이상으로 상향 검토 (후속). 넘길 것 같으면 만료 전 토픽을 백업 |
| AWS 가 먼저 살아나 AWS core-service consumer 가 Failback 전에 소비 시작 | DR 기간 쓰기가 없는 RDS 에 지급 → Failback 동기화와 충돌 | AWS 복구를 확인하면 **AWS core-service 를 0 으로 축소(또는 `REWARD_STREAM_ENABLED=false`)한 채 유지**, Failback 6단계에서만 재개 |
| AWS 영구 소실 | MSK·Redis 당첨 기록 소실 → **미지급 당첨자 명단을 복원할 수 없다** | 비즈니스 결정 (해당 이벤트 재진행 / 참여자 일괄 보상). RPO 범위의 데이터 손실로 받아들인다 |

- 부분 지급 상태의 **판정 기준**은 없어진다. 대신 lag 를 낮게 유지하는 것이 RPO 를 줄이는 수단이다 (consumer lag 알람, 피크 전 파티션·consumer 수 점검).
- 지급은 건별로 원자적이다 (원장 INSERT + 지갑 UPDATE 한 트랜잭션). "이벤트 단위 원자성"만 포기한다.
- 반영이 끝난 뒤 **완료 확인**: 이벤트별 Redis 당첨자 Set ↔ 원장(`source=EVENT, reference_id=eventId`) 대사. Redis 가 소실됐으면 MSK 메시지가 유일한 근거다.
- 운영: 장애 시점에 열려 있던 이벤트는 event-service 재개 전에 닫는다 (Failback 후 새 참여 방지). DR 중 "이벤트 보상은 서비스 정상화 후 지급" 공지. DLQ(`point.reward.dlq`) 건도 Failback 때 처리한다.

## 고려한 대안
| 대안 | 장점 | 단점 | 판단 |
|---|---|---|---|
| ADR-0017 유지 (일괄 정산) | DR 에서 이벤트 단위 판정·재정산 | 당첨 후 지급 지연, 정산 운영 부담, 자동화 미비 | 서비스 흐름 문제로 철회 |
| 즉시 지급 + 정산 기능을 설정으로 공존 | 되돌리기 쉬움 | 두 경로를 계속 테스트·운영해야 함, 설정 실수 시 이중 지급 경로 혼재 | 복잡도 대비 이득 없음 |
| 즉시 지급 + MSK → Cloud SQL inbox Sink | 즉시 지급 유지, DR 에서 미반영분 일부 복구 | Schema Registry·Sink 운영, Sink lag 만큼은 여전히 손실 | 즉시 지급이 확정됐으므로 **후속 검토 1순위** |
| 즉시 지급 + 이벤트 종료 후 대사 배치 | 단순, 누락·초과를 사후 발견 | 실시간 보호 아님 | 후속 과제로 채택 (아래) |

## 결과
- (+) 당첨 직후 잔액·내역 반영 — 사용자 흐름 정상화, 프론트 문구 "곧 적립돼요"
- (+) 이벤트 종료 후 운영자 작업 없음, 관리자 정산 API 제거로 공격 표면 축소 (토큰 검사 코드는 공통 모듈 정리 때 함께 제거)
- (+) 퀴즈·출석이 같은 consumer 경로 → 코드·테스트 단순화
- (−) 재해 시 이벤트 단위 원자성·판정 기준 상실 (위 표). Failback 으로 대부분 보충되지만 AWS 영구 소실 시 미지급 명단 복원 불가
- (−) 피크 중 consumer 가 원장 행 잠금을 다시 잡는다 (ADR-0017 의 lag 감소 효과 상실) → 부하 테스트로 lag 를 다시 측정할 것
- 후속: Redis 당첨자 Set ↔ 원장(`source=EVENT, reference_id=eventId`) **대사 배치** (domain-model §4), consumer lag 알람, `point.reward.requested` 보존 기간 상향 검토, Failback 오프셋 되감기 스크립트, inbox Sink 재검토
